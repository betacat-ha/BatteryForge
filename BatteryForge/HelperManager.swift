import BatteryForgeCore
import Foundation
import ServiceManagement
import Combine

enum HelperConstants {
    nonisolated static let machServiceName = "com.betacat.batteryforge.helper"
    nonisolated static let plistName = "com.betacat.batteryforge.helper.plist"
    nonisolated static let bundledVersion = Bundle.main.object(forInfoDictionaryKey: "BatteryForgeHelperVersion") as? String
    nonisolated static let bundledBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    nonisolated static let buildFilePath = "/Library/Application Support/BatteryForge/helper-build"
    nonisolated static let versionFilePath = "/Library/Application Support/BatteryForge/helper-version"
}

@objc(BatteryHelperProtocol)
protocol BatteryHelperProtocol {
    func configure(
        lower: Int,
        upper: Int,
        highLoad: Bool,
        stressWorkers: Int,
        gpuLoad: Bool,
        thermalProtectionEnabled: Bool,
        thermalThreshold: Double,
        reply: @escaping (Bool, String) -> Void
    )
    func stop(reply: @escaping (Bool, String) -> Void)
    func status(reply: @escaping (Bool, String, Int, Bool, String) -> Void)
    func history(reply: @escaping (String) -> Void)
    func clearHistory(reply: @escaping (Bool, String) -> Void)
}

private struct HelperMessagePayload: Decodable {
    let key: String
    let arguments: [String]
}

private func localizedPercent(_ rawValue: String) -> String {
    guard let value = Double(rawValue) else { return rawValue }
    return AppLanguage.localizedPercent(value)
}

func localizedHelperMessage(_ rawValue: String) -> String {
    guard let data = rawValue.data(using: .utf8),
          let payload = try? JSONDecoder().decode(HelperMessagePayload.self, from: data)
    else { return rawValue }

    let format: String
    switch payload.key {
    case "helper.runtime.updated_and_stopped":
        format = AppLanguage.localized("helper.runtime.updated_and_stopped")
    case "helper.runtime.invalid_thresholds":
        format = AppLanguage.localized("helper.runtime.invalid_thresholds")
        return String.localizedStringWithFormat(format, AppLanguage.localizedPercent(10))
    case "helper.runtime.started":
        format = AppLanguage.localized("helper.runtime.started")
    case "helper.runtime.stopping":
        format = AppLanguage.localized("helper.runtime.stopping")
    case "helper.runtime.stopped":
        format = AppLanguage.localized("helper.runtime.stopped")
    case "helper.runtime.battery_unavailable":
        format = AppLanguage.localized("helper.runtime.battery_unavailable")
    case "helper.runtime.thermal_paused":
        guard payload.arguments.count == 2 else { return rawValue }
        format = AppLanguage.localized("helper.runtime.thermal_paused")
        return String.localizedStringWithFormat(format, payload.arguments[0], payload.arguments[1])
    case "helper.runtime.power_control_failed":
        format = AppLanguage.localized("helper.runtime.power_control_failed")
    case "helper.runtime.restore_failed":
        format = AppLanguage.localized("helper.runtime.restore_failed")
    case "helper.runtime.charging":
        guard payload.arguments.count == 2 else { return rawValue }
        format = AppLanguage.localized("helper.runtime.charging")
        return String.localizedStringWithFormat(
            format,
            localizedPercent(payload.arguments[0]),
            localizedPercent(payload.arguments[1])
        )
    case "helper.runtime.waiting_for_power":
        guard payload.arguments.count == 1 else { return rawValue }
        format = AppLanguage.localized("helper.runtime.waiting_for_power")
        return String.localizedStringWithFormat(format, localizedPercent(payload.arguments[0]))
    case "helper.runtime.discharging":
        guard payload.arguments.count == 2 else { return rawValue }
        format = AppLanguage.localized("helper.runtime.discharging")
        return String.localizedStringWithFormat(
            format,
            localizedPercent(payload.arguments[0]),
            localizedPercent(payload.arguments[1])
        )
    case "helper.runtime.discharging_cpu":
        guard payload.arguments.count == 3 else { return rawValue }
        format = AppLanguage.localized("helper.runtime.discharging_cpu")
        return String.localizedStringWithFormat(
            format,
            localizedPercent(payload.arguments[0]),
            localizedPercent(payload.arguments[1]),
            payload.arguments[2]
        )
    case "helper.runtime.discharging_cpu_gpu":
        guard payload.arguments.count == 3 else { return rawValue }
        format = AppLanguage.localized("helper.runtime.discharging_cpu_gpu")
        return String.localizedStringWithFormat(
            format,
            localizedPercent(payload.arguments[0]),
            localizedPercent(payload.arguments[1]),
            payload.arguments[2]
        )
    default:
        return rawValue
    }
    return format
}

struct CycleHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: String
    let batteryPercent: Int?
    let lower: Int
    let upper: Int
    let completedCycles: Int
    let highLoad: Bool
    let stressWorkers: Int
    let gpuLoad: Bool
    let message: String
}

enum HelperState: Equatable {
    case notRegistered
    case installing
    case uninstalling
    case enabled
    case unavailable(String)

    var title: String {
        switch self {
        case .notRegistered: AppLanguage.localized("helper.state.not_installed")
        case .installing: AppLanguage.localized("helper.state.installing")
        case .uninstalling: AppLanguage.localized("helper.state.uninstalling")
        case .enabled: AppLanguage.localized("helper.state.enabled")
        case .unavailable: AppLanguage.localized("helper.state.unavailable")
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
    @Published private(set) var bundledVersion: String? = HelperConstants.bundledVersion
    @Published private(set) var installedVersion: String?
    @Published private(set) var installedBuild: String?
    @Published private(set) var historyEntries: [CycleHistoryEntry] = []
    @Published private(set) var historyUpdatedAt: Date?
    @Published private(set) var historyError: String?
    @Published private(set) var isHistoryLoading = false

    private let previousService = SMAppService.daemon(plistName: "cn.com.betacat.battery.helper.plist")
    private var connection: NSXPCConnection?
    private let installedHelperPath = "/Library/PrivilegedHelperTools/com.betacat.batteryforge.helper"

    var requiresUpdate: Bool {
        guard state == .enabled else { return false }
        guard let bundledVersion else { return true }
        guard let installedVersion else { return true }
        return HelperBuildVersion(version: installedVersion, build: installedBuild).needsUpdate(
            to: HelperBuildVersion(version: bundledVersion, build: HelperConstants.bundledBuild)
        )
    }

    var versionDescription: String? {
        guard let installedVersion else { return nil }
        return String.localizedStringWithFormat(
            AppLanguage.localized("helper.version.current"),
            HelperBuildVersion(version: installedVersion, build: installedBuild).displayValue
        )
    }

    var updateDescription: String? {
        guard requiresUpdate, let bundledVersion else { return nil }
        let installed = installedVersion.map {
            HelperBuildVersion(version: $0, build: installedBuild).displayValue
        } ?? AppLanguage.localized("helper.version.unknown")
        return String.localizedStringWithFormat(
            AppLanguage.localized("helper.update.description"),
            installed,
            HelperBuildVersion(version: bundledVersion, build: HelperConstants.bundledBuild).displayValue
        )
    }

    init() {
        refreshHelperVersions()
        refreshRegistrationState()
        if state == .enabled { refreshStatus() }
    }

    func refreshRegistrationState() {
        if state == .installing || state == .uninstalling { return }
        let isInstalled = FileManager.default.fileExists(atPath: installedHelperPath)
        state = isInstalled ? .enabled : .notRegistered
        if isInstalled {
            refreshHelperVersions()
        } else {
            installedVersion = nil
            installedBuild = nil
        }
    }

    func install() {
        guard state != .installing, state != .uninstalling else { return }
        guard let helperURL = Bundle.main.url(forResource: "BatteryForgeHelper", withExtension: nil) else {
            state = .unavailable(AppLanguage.localized("helper.error.executable_missing"))
            return
        }
        let plistURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons")
            .appendingPathComponent(HelperConstants.plistName)
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            state = .unavailable(AppLanguage.localized("helper.error.launch_daemon_missing"))
            return
        }
        // Remove the earlier SMAppService registration before migrating to the
        // locally installed daemon. This is harmless when it was never used.
        try? previousService.unregister()
        state = .installing
        message = AppLanguage.localized("helper.status.authorization_prompt")
        Task.detached {
            do {
                try HelperInstaller.install(helperURL: helperURL, plistURL: plistURL)
                await MainActor.run {
                    self.state = .enabled
                    self.message = AppLanguage.localized("helper.status.installed")
                    self.connection?.invalidate()
                    self.connection = nil
                    self.refreshHelperVersions()
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

    func uninstall() {
        guard state != .installing, state != .uninstalling else { return }
        guard FileManager.default.fileExists(atPath: installedHelperPath) else {
            state = .notRegistered
            installedVersion = nil
            installedBuild = nil
            return
        }

        connection?.invalidate()
        connection = nil
        state = .uninstalling
        message = AppLanguage.localized("helper.status.authorization_prompt")
        Task.detached {
            do {
                try HelperInstaller.uninstall()
                await MainActor.run {
                    self.state = .notRegistered
                    self.installedVersion = nil
                    self.installedBuild = nil
                    self.isCycleRunning = false
                    self.phase = "idle"
                    self.completedCycles = 0
                    self.highLoadRunning = false
                    self.historyEntries = []
                    self.historyUpdatedAt = Date()
                    self.message = AppLanguage.localized("helper.status.uninstalled")
                }
            } catch {
                await MainActor.run {
                    let isInstalled = FileManager.default.fileExists(atPath: self.installedHelperPath)
                    self.state = isInstalled ? .enabled : .notRegistered
                    self.message = error.localizedDescription
                    self.refreshHelperVersions()
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
        thermalProtectionEnabled: Bool,
        thermalThreshold: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        refreshRegistrationState()
        guard state == .enabled else {
            completion(.failure(HelperManagerError.notEnabled))
            return
        }
        guard !requiresUpdate else {
            completion(.failure(HelperManagerError.helper(
                updateDescription ?? AppLanguage.localized("helper.update.available")
            )))
            return
        }
        proxy { proxy in
            proxy.configure(
                lower: lower,
                upper: upper,
                highLoad: highLoad,
                stressWorkers: stressWorkers,
                gpuLoad: gpuLoad,
                thermalProtectionEnabled: thermalProtectionEnabled,
                thermalThreshold: thermalThreshold
            ) { [weak self] success, message in
                Task { @MainActor in
                    let localizedMessage = localizedHelperMessage(message)
                    self?.message = localizedMessage
                    self?.refreshStatus()
                    success
                        ? completion(.success(()))
                        : completion(.failure(HelperManagerError.helper(localizedMessage)))
                }
            }
        } onError: { completion(.failure($0)) }
    }

    func stopCycle(completion: @escaping (Result<Void, Error>) -> Void) {
        // A stop command must not wait behind status requests already queued
        // on the long-lived connection.
        connection?.invalidate()
        connection = nil
        proxy { proxy in
            proxy.stop { [weak self] success, message in
                Task { @MainActor in
                    let localizedMessage = localizedHelperMessage(message)
                    self?.message = localizedMessage
                    self?.refreshStatus()
                    success
                        ? completion(.success(()))
                        : completion(.failure(HelperManagerError.helper(localizedMessage)))
                }
            }
        } onError: { completion(.failure($0)) }
    }

    func refreshStatus(completion: (() -> Void)? = nil) {
        guard state == .enabled else { return }
        proxy { proxy in
            proxy.status { [weak self] running, phase, cycles, highLoad, message in
                Task { @MainActor in
                    self?.isCycleRunning = running
                    self?.phase = phase
                    self?.completedCycles = cycles
                    self?.highLoadRunning = highLoad
                    self?.message = localizedHelperMessage(message)
                    completion?()
                }
            }
        } onError: { [weak self] error in
            self?.message = error.localizedDescription
            completion?()
        }
    }

    func refreshHistory() {
        refreshRegistrationState()
        guard state == .enabled, !requiresUpdate else {
            historyEntries = []
            historyUpdatedAt = Date()
            return
        }
        isHistoryLoading = true
        historyError = nil
        proxy { proxy in
            proxy.history { [weak self] payload in
                Task { @MainActor in
                    defer { self?.isHistoryLoading = false }
                    guard let data = payload.data(using: .utf8),
                          let entries = try? JSONDecoder().decode([CycleHistoryEntry].self, from: data)
                    else {
                        self?.historyError = AppLanguage.localized("history.error.read")
                        return
                    }
                    self?.historyEntries = entries.sorted { $0.timestamp > $1.timestamp }
                    self?.historyUpdatedAt = Date()
                }
            }
        } onError: { [weak self] error in
            self?.isHistoryLoading = false
            self?.historyError = error.localizedDescription
        }
    }

    func clearHistory() {
        guard state == .enabled, !requiresUpdate else { return }
        isHistoryLoading = true
        historyError = nil
        proxy { proxy in
            proxy.clearHistory { [weak self] success, message in
                Task { @MainActor in
                    self?.isHistoryLoading = false
                    if success {
                        self?.historyEntries = []
                        self?.historyUpdatedAt = Date()
                    } else {
                        self?.historyError = message
                    }
                }
            }
        } onError: { [weak self] error in
            self?.isHistoryLoading = false
            self?.historyError = error.localizedDescription
        }
    }

    private func proxy(_ operation: (BatteryHelperProtocol) -> Void, onError: @escaping (Error) -> Void) {
        let connection = ensureConnection()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            Task { @MainActor in
                if self.connection === connection {
                    self.connection?.invalidate()
                    self.connection = nil
                }
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
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            Task { @MainActor in
                guard let newConnection, self?.connection === newConnection else { return }
                self?.connection = nil
            }
        }
        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func refreshHelperVersions() {
        bundledVersion = HelperConstants.bundledVersion
        guard FileManager.default.fileExists(atPath: installedHelperPath) else {
            installedVersion = nil
            installedBuild = nil
            return
        }
        let rawValue = try? String(contentsOfFile: HelperConstants.versionFilePath, encoding: .utf8)
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        installedVersion = value?.isEmpty == false ? value : nil
        let rawBuild = try? String(contentsOfFile: HelperConstants.buildFilePath, encoding: .utf8)
        let build = rawBuild?.trimmingCharacters(in: .whitespacesAndNewlines)
        installedBuild = build?.isEmpty == false ? build : nil
    }
}

enum HelperManagerError: LocalizedError {
    case notEnabled
    case connectionFailed
    case helper(String)

    var errorDescription: String? {
        switch self {
        case .notEnabled: AppLanguage.localized("helper.error.not_enabled")
        case .connectionFailed: AppLanguage.localized("helper.error.connection_failed")
        case .helper(let message): message
        }
    }
}

private enum HelperInstaller {
    nonisolated static func install(helperURL: URL, plistURL: URL) throws {
        let helperDestination = "/Library/PrivilegedHelperTools/com.betacat.batteryforge.helper"
        let plistDestination = "/Library/LaunchDaemons/com.betacat.batteryforge.helper.plist"
        let versionDestination = HelperConstants.versionFilePath
        let buildDestination = HelperConstants.buildFilePath
        guard let version = HelperConstants.bundledVersion,
              let build = HelperConstants.bundledBuild else {
            throw HelperManagerError.helper(AppLanguage.localized("helper.error.build_metadata_missing"))
        }
        let command = [
            "/bin/mkdir -p '/Library/Application Support/BatteryForge'",
            "/usr/bin/touch '/Library/Application Support/BatteryForge/force-stop'",
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
            "/bin/echo \(shellQuote(version)) > \(shellQuote(versionDestination))",
            "/usr/sbin/chown root:wheel \(shellQuote(versionDestination))",
            "/bin/chmod 644 \(shellQuote(versionDestination))",
            "/bin/echo \(shellQuote(build)) > \(shellQuote(buildDestination))",
            "/usr/sbin/chown root:wheel \(shellQuote(buildDestination))",
            "/bin/chmod 644 \(shellQuote(buildDestination))",
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
            throw HelperManagerError.helper(
                detail?.isEmpty == false ? detail! : AppLanguage.localized("helper.error.install_cancelled")
            )
        }
    }

    nonisolated static func uninstall() throws {
        let command = [
            "/bin/launchctl bootout system/com.betacat.batteryforge.helper 2>/dev/null || true",
            "/bin/launchctl bootout system/cn.com.betacat.battery.helper 2>/dev/null || true",
            "/bin/rm -f /Library/PrivilegedHelperTools/com.betacat.batteryforge.helper",
            "/bin/rm -f /Library/LaunchDaemons/com.betacat.batteryforge.helper.plist",
            "/bin/rm -f /Library/PrivilegedHelperTools/cn.com.betacat.battery.helper",
            "/bin/rm -f /Library/LaunchDaemons/cn.com.betacat.battery.helper.plist",
            "/bin/rm -f \(shellQuote(HelperConstants.versionFilePath))",
            "/bin/rm -f \(shellQuote(HelperConstants.buildFilePath))",
            "/bin/rm -f '/Library/Application Support/BatteryForge/force-stop'"
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
            throw HelperManagerError.helper(
                detail?.isEmpty == false ? detail! : AppLanguage.localized("helper.error.uninstall_cancelled")
            )
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
