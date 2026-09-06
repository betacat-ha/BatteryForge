import Foundation
import ServiceManagement
import Combine

enum HelperConstants {
    nonisolated static let machServiceName = "com.betacat.batteryforge.helper"
    nonisolated static let plistName = "com.betacat.batteryforge.helper.plist"
}

@objc(BatteryHelperProtocol)
protocol BatteryHelperProtocol {
    func configure(
        lower: Int,
        upper: Int,
        highLoad: Bool,
        stressWorkers: Int,
        gpuLoad: Bool,
        reply: @escaping (Bool, String) -> Void
    )
    func stop(reply: @escaping (Bool, String) -> Void)
    func status(reply: @escaping (Bool, String, Int, Bool, String) -> Void)
}

enum HelperState: Equatable {
    case notRegistered
    case installing
    case enabled
    case unavailable(String)

    var title: String {
        switch self {
        case .notRegistered: "后台服务未安装"
        case .installing: "正在安装后台服务"
        case .enabled: "后台服务已启用"
        case .unavailable: "后台服务不可用"
        }
    }
}

@MainActor
final class HelperManager: ObservableObject {
    @Published private(set) var state: HelperState = .notRegistered
    @Published private(set) var isCycleRunning = false
    @Published private(set) var phase = "idle"
    @Published private(set) var completedCycles = 0
    @Published private(set) var highLoadRunning = false
    @Published private(set) var message = ""

    private let previousService = SMAppService.daemon(plistName: "cn.com.betacat.battery.helper.plist")
    private var connection: NSXPCConnection?
    private let installedHelperPath = "/Library/PrivilegedHelperTools/com.betacat.batteryforge.helper"

    init() {
        refreshRegistrationState()
        if state == .enabled { refreshStatus() }
    }

    func refreshRegistrationState() {
        if state == .installing { return }
        state = FileManager.default.fileExists(atPath: installedHelperPath) ? .enabled : .notRegistered
    }

    func install() {
        guard state != .installing else { return }
        guard let helperURL = Bundle.main.url(forResource: "BatteryForgeHelper", withExtension: nil) else {
            state = .unavailable("应用包中缺少后台服务文件")
            return
        }
        let plistURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons")
            .appendingPathComponent(HelperConstants.plistName)
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            state = .unavailable("应用包中缺少 LaunchDaemon 配置")
            return
        }
        // Remove the earlier SMAppService registration before migrating to the
        // locally installed daemon. This is harmless when it was never used.
        try? previousService.unregister()
        state = .installing
        message = "系统将询问一次管理员密码"
        Task.detached {
            do {
                try HelperInstaller.install(helperURL: helperURL, plistURL: plistURL)
                await MainActor.run {
                    self.state = .enabled
                    self.message = "后台服务已安装，后续无需重复授权"
                    self.connection?.invalidate()
                    self.connection = nil
                    self.refreshStatus()
                }
            } catch {
                await MainActor.run {
                    self.state = .unavailable(error.localizedDescription)
                    self.message = error.localizedDescription
                }
            }
        }
    }

    func startCycle(
        lower: Int,
        upper: Int,
        highLoad: Bool,
        stressWorkers: Int,
        gpuLoad: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        refreshRegistrationState()
        guard state == .enabled else {
            completion(.failure(HelperManagerError.notEnabled))
            return
        }
        proxy { proxy in
            proxy.configure(
                lower: lower,
                upper: upper,
                highLoad: highLoad,
                stressWorkers: stressWorkers,
                gpuLoad: gpuLoad
            ) { [weak self] success, message in
                Task { @MainActor in
                    self?.message = message
                    self?.refreshStatus()
                    success ? completion(.success(())) : completion(.failure(HelperManagerError.helper(message)))
                }
            }
        } onError: { completion(.failure($0)) }
    }

    func stopCycle(completion: @escaping (Result<Void, Error>) -> Void) {
        proxy { proxy in
            proxy.stop { [weak self] success, message in
                Task { @MainActor in
                    self?.message = message
                    self?.refreshStatus()
                    success ? completion(.success(())) : completion(.failure(HelperManagerError.helper(message)))
                }
            }
        } onError: { completion(.failure($0)) }
    }

    func refreshStatus() {
        guard state == .enabled else { return }
        proxy { proxy in
            proxy.status { [weak self] running, phase, cycles, highLoad, message in
                Task { @MainActor in
                    self?.isCycleRunning = running
                    self?.phase = phase
                    self?.completedCycles = cycles
                    self?.highLoadRunning = highLoad
                    self?.message = message
                }
            }
        } onError: { [weak self] error in self?.message = error.localizedDescription }
    }

    private func proxy(_ operation: (BatteryHelperProtocol) -> Void, onError: @escaping (Error) -> Void) {
        let connection = ensureConnection()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            Task { @MainActor in
                self.connection?.invalidate()
                self.connection = nil
                onError(error)
            }
        }) as? BatteryHelperProtocol else {
            onError(HelperManagerError.connectionFailed)
            return
        }
        operation(proxy)
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection { return connection }
        let newConnection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: BatteryHelperProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        newConnection.resume()
        connection = newConnection
        return newConnection
    }
}

enum HelperManagerError: LocalizedError {
    case notEnabled
    case connectionFailed
    case helper(String)

    var errorDescription: String? {
        switch self {
        case .notEnabled: "请先安装并批准后台服务"
        case .connectionFailed: "无法连接后台服务"
        case .helper(let message): message
        }
    }
}

private enum HelperInstaller {
    nonisolated static func install(helperURL: URL, plistURL: URL) throws {
        let helperDestination = "/Library/PrivilegedHelperTools/com.betacat.batteryforge.helper"
        let plistDestination = "/Library/LaunchDaemons/com.betacat.batteryforge.helper.plist"
        let command = [
            "/bin/launchctl bootout system/com.betacat.batteryforge.helper 2>/dev/null || true",
            "/bin/launchctl bootout system/cn.com.betacat.battery.helper 2>/dev/null || true",
            "/bin/rm -f /Library/PrivilegedHelperTools/cn.com.betacat.battery.helper",
            "/bin/rm -f /Library/LaunchDaemons/cn.com.betacat.battery.helper.plist",
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/bin/cp \(shellQuote(helperURL.path)) \(shellQuote(helperDestination))",
            "/usr/sbin/chown root:wheel \(shellQuote(helperDestination))",
            "/bin/chmod 755 \(shellQuote(helperDestination))",
            "/bin/cp \(shellQuote(plistURL.path)) \(shellQuote(plistDestination))",
            "/usr/sbin/chown root:wheel \(shellQuote(plistDestination))",
            "/bin/chmod 644 \(shellQuote(plistDestination))",
            "/bin/launchctl bootstrap system \(shellQuote(plistDestination))"
        ].joined(separator: "; ")
        let appleScript = "do shell script \"\(appleScriptQuote(command))\" with administrator privileges"

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HelperManagerError.helper(detail?.isEmpty == false ? detail! : "安装已取消")
        }
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func appleScriptQuote(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
