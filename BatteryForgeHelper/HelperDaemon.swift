import Foundation
import IOKit
import IOKit.pwr_mgt
import Metal
import Security

private struct CycleConfiguration: Codable, Equatable {
    var enabled = false
    var lower = 25
    var upper = 80
    var highLoad = true
    var stressWorkers = max(ProcessInfo.processInfo.activeProcessorCount / 2, 1)
    var gpuLoad = true
    var completedCycles = 0
    var phase = "idle"
    var message = ""
    var sleepOverrideActive = false
    var sleepWasDisabledBeforeDischarge = false

    private enum CodingKeys: String, CodingKey {
        case enabled, lower, upper, highLoad, stressWorkers, gpuLoad, completedCycles
        case phase, message, sleepOverrideActive, sleepWasDisabledBeforeDischarge
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        lower = try values.decodeIfPresent(Int.self, forKey: .lower) ?? 25
        upper = try values.decodeIfPresent(Int.self, forKey: .upper) ?? 80
        highLoad = try values.decodeIfPresent(Bool.self, forKey: .highLoad) ?? true
        stressWorkers = try values.decodeIfPresent(Int.self, forKey: .stressWorkers)
            ?? max(ProcessInfo.processInfo.activeProcessorCount / 2, 1)
        gpuLoad = try values.decodeIfPresent(Bool.self, forKey: .gpuLoad) ?? true
        completedCycles = try values.decodeIfPresent(Int.self, forKey: .completedCycles) ?? 0
        phase = try values.decodeIfPresent(String.self, forKey: .phase) ?? "idle"
        message = try values.decodeIfPresent(String.self, forKey: .message) ?? ""
        sleepOverrideActive = try values.decodeIfPresent(Bool.self, forKey: .sleepOverrideActive) ?? false
        sleepWasDisabledBeforeDischarge = try values.decodeIfPresent(
            Bool.self,
            forKey: .sleepWasDisabledBeforeDischarge
        ) ?? false
    }
}

final class HelperDaemon: NSObject, NSXPCListenerDelegate, BatteryHelperProtocol {
    static let shared = HelperDaemon()

    private var configuration = CycleConfiguration()
    private var appliedAction: PowerAction?
    private var timer: Timer?
    private let stressWorker = HelperStressWorker()
    private var powerConnection: io_connect_t = 0
    private var powerPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0

    private let configurationURL = URL(fileURLWithPath: "/Library/Application Support/BatteryForge/config.json")
    private let forcedStopURL = URL(fileURLWithPath: "/Library/Application Support/BatteryForge/force-stop")
    private let versionURL = URL(fileURLWithPath: "/Library/Application Support/BatteryForge/helper-version")

    func run() {
        try? helperVersion.write(to: versionURL, atomically: true, encoding: .utf8)
        loadConfiguration()
        applyForcedStopIfRequested()
        restorePower()
        installSignalHandlers()
        installSleepHandler()

        let listener = NSXPCListener(machServiceName: helperMachServiceName)
        listener.delegate = self
        listener.resume()

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        tick()
        RunLoop.main.run()
    }

    private func applyForcedStopIfRequested() {
        guard FileManager.default.fileExists(atPath: forcedStopURL.path) else { return }
        configuration.enabled = false
        configuration.phase = "idle"
        configuration.message = HelperMessagePayload.encode("helper.runtime.updated_and_stopped")
        try? FileManager.default.removeItem(at: forcedStopURL)
        saveConfiguration()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard validateClient(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: BatteryHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func configure(
        lower: Int,
        upper: Int,
        highLoad: Bool,
        stressWorkers: Int,
        gpuLoad: Bool,
        reply: @escaping (Bool, String) -> Void
    ) {
        DispatchQueue.main.async {
            guard lower >= 10, upper <= 100, upper - lower >= 10 else {
                reply(false, HelperMessagePayload.encode("helper.runtime.invalid_thresholds"))
                return
            }
            self.configuration.enabled = true
            self.configuration.lower = lower
            self.configuration.upper = upper
            self.configuration.highLoad = highLoad
            self.configuration.stressWorkers = min(max(stressWorkers, 1), ProcessInfo.processInfo.activeProcessorCount)
            self.configuration.gpuLoad = gpuLoad
            self.configuration.completedCycles = 0
            self.configuration.phase = "preparing"
            self.configuration.message = HelperMessagePayload.encode("helper.runtime.started")
            self.saveConfiguration()
            self.tick()
            reply(true, self.configuration.message)
        }
    }

    func stop(reply: @escaping (Bool, String) -> Void) {
        DispatchQueue.main.async(qos: .userInteractive) {
            NSLog("BatteryForge stop requested")
            self.configuration.enabled = false
            self.configuration.phase = "stopping"
            self.configuration.message = HelperMessagePayload.encode("helper.runtime.stopping")
            self.saveConfiguration()
            self.stressWorker.stop()
            do {
                var restorationError: Error?
                do { try DirectPowerControl.apply(.normal) } catch { restorationError = error }
                do { try self.restoreSleepPolicy() } catch {
                    if restorationError == nil { restorationError = error }
                }
                if let restorationError { throw restorationError }
                self.appliedAction = .normal
                self.configuration.phase = "idle"
                self.configuration.message = HelperMessagePayload.encode("helper.runtime.stopped")
                self.saveConfiguration()
                NSLog("BatteryForge stop completed")
                reply(true, self.configuration.message)
            } catch {
                self.configuration.phase = "failed"
                self.configuration.message = HelperMessagePayload.encode("helper.runtime.restore_failed")
                self.saveConfiguration()
                NSLog("BatteryForge stop failed: \(error)")
                reply(false, self.configuration.message)
            }
        }
    }

    func status(reply: @escaping (Bool, String, Int, Bool, String) -> Void) {
        DispatchQueue.main.async {
            reply(
                self.configuration.enabled,
                self.configuration.phase,
                self.configuration.completedCycles,
                self.stressWorker.isRunning,
                self.configuration.message
            )
        }
    }

    private func tick() {
        guard configuration.enabled else {
            stressWorker.stop()
            return
        }
        let configurationBeforeTick = configuration
        guard let battery = HelperBatteryReader.current() else {
            failSafely(HelperMessagePayload.encode("helper.runtime.battery_unavailable"))
            return
        }

        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical {
            failSafely(HelperMessagePayload.encode("helper.runtime.thermal_stop"))
            return
        }

        let previousPhase = configuration.phase
        let targetPhase: String
        if battery.percent <= configuration.lower {
            targetPhase = "charging"
        } else if battery.percent >= configuration.upper {
            targetPhase = "discharging"
        } else if previousPhase == "discharging" {
            targetPhase = "discharging"
        } else {
            targetPhase = "charging"
        }

        if targetPhase == "charging" {
            stressWorker.stop()
            do {
                try applyIfNeeded(.normal)
                if previousPhase == "discharging" { configuration.completedCycles += 1 }
                configuration.phase = "charging"
                configuration.message = battery.adapterPresent
                    ? HelperMessagePayload.encode(
                        "helper.runtime.charging",
                        [battery.percent, configuration.upper]
                    )
                    : HelperMessagePayload.encode("helper.runtime.waiting_for_power", [battery.percent])
            } catch {
                NSLog("BatteryForge charging transition failed: \(error)")
                failSafely(HelperMessagePayload.encode("helper.runtime.power_control_failed"))
                return
            }
        } else {
            do {
                if battery.adapterPresent { try applyIfNeeded(.discharge) }
                if configuration.highLoad {
                    stressWorker.start(
                        workerCount: configuration.stressWorkers,
                        gpuEnabled: configuration.gpuLoad
                    )
                } else {
                    stressWorker.stop()
                }
                configuration.phase = "discharging"
                if stressWorker.isRunning {
                    let key = stressWorker.isGPURunning
                        ? "helper.runtime.discharging_cpu_gpu"
                        : "helper.runtime.discharging_cpu"
                    configuration.message = HelperMessagePayload.encode(
                        key,
                        [battery.percent, configuration.lower, stressWorker.workerCount]
                    )
                } else {
                    configuration.message = HelperMessagePayload.encode(
                        "helper.runtime.discharging",
                        [battery.percent, configuration.lower]
                    )
                }
            } catch {
                NSLog("BatteryForge discharging transition failed: \(error)")
                failSafely(HelperMessagePayload.encode("helper.runtime.power_control_failed"))
                return
            }
        }
        if configuration != configurationBeforeTick { saveConfiguration() }
    }

    private func applyIfNeeded(_ action: PowerAction) throws {
        guard appliedAction != action else { return }
        if action == .normal {
            // Restore AC first, then permit sleep again.
            do {
                try DirectPowerControl.apply(.normal)
            } catch {
                // Sleep restoration must not depend on the SMC command
                // succeeding; leaving a global sleep override behind is worse.
                try? restoreSleepPolicy()
                throw error
            }
            try restoreSleepPolicy()
            appliedAction = .normal
        } else {
            // Once adapter input is cut, macOS considers the machine to be on
            // battery and clamshell mode would force sleep. Block it first.
            try enableSleepPrevention()
            do {
                try DirectPowerControl.apply(.discharge)
                appliedAction = .discharge
            } catch {
                try? restoreSleepPolicy()
                throw error
            }
        }
    }

    private func failSafely(_ message: String) {
        stressWorker.stop()
        restorePower()
        configuration.enabled = false
        configuration.phase = "failed"
        configuration.message = message
        saveConfiguration()
    }

    private func restorePower() {
        try? DirectPowerControl.apply(.normal)
        try? restoreSleepPolicy()
        appliedAction = .normal
    }

    private func enableSleepPrevention() throws {
        guard !configuration.sleepOverrideActive else { return }
        configuration.sleepWasDisabledBeforeDischarge = SleepPolicy.isSleepDisabled()
        configuration.sleepOverrideActive = true
        // Persist before changing the global setting so a launchd restart can
        // always tell that this daemon owns the override and undo it.
        saveConfiguration()
        do {
            try SleepPolicy.setSleepDisabled(true)
        } catch {
            configuration.sleepOverrideActive = false
            saveConfiguration()
            throw error
        }
    }

    private func restoreSleepPolicy() throws {
        guard configuration.sleepOverrideActive else { return }
        if !configuration.sleepWasDisabledBeforeDischarge {
            try SleepPolicy.setSleepDisabled(false)
        }
        configuration.sleepOverrideActive = false
        configuration.sleepWasDisabledBeforeDischarge = false
        saveConfiguration()
    }

    private func loadConfiguration() {
        guard let data = try? Data(contentsOf: configurationURL),
              let saved = try? JSONDecoder().decode(CycleConfiguration.self, from: data)
        else { return }
        configuration = saved
    }

    private func saveConfiguration() {
        do {
            let directory = configurationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(configuration)
            try data.write(to: configurationURL, options: .atomic)
        } catch {
            NSLog("Battery helper could not persist configuration: \(error)")
        }
    }

    private func installSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        for signalNumber in [SIGTERM, SIGINT] {
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.configuration.enabled = false
                self?.restorePower()
                self?.saveConfiguration()
                exit(0)
            }
            source.resume()
            SignalStorage.sources.append(source)
        }
    }

    private func installSleepHandler() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerConnection = IORegisterForSystemPower(context, &powerPort, { context, _, messageType, argument in
            guard let context else { return }
            Unmanaged<HelperDaemon>.fromOpaque(context).takeUnretainedValue()
                .handlePowerMessage(messageType, argument)
        }, &powerNotifier)
        guard powerConnection != MACH_PORT_NULL,
              let powerPort,
              let source = IONotificationPortGetRunLoopSource(powerPort)?.takeUnretainedValue()
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func handlePowerMessage(_ type: natural_t, _ argument: UnsafeMutableRawPointer?) {
        let canSleep: natural_t = 0xE000_0270
        let willSleep: natural_t = 0xE000_0280
        let didWake: natural_t = 0xE000_0300
        if type == canSleep {
            IOAllowPowerChange(powerConnection, Int(bitPattern: argument))
        } else if type == willSleep {
            stressWorker.stop()
            restorePower()
            IOAllowPowerChange(powerConnection, Int(bitPattern: argument))
        } else if type == didWake {
            appliedAction = nil
            tick()
        }
    }

    private func validateClient(_ connection: NSXPCConnection) -> Bool {
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var unmanagedInformation: CFDictionary?
        let flags = SecCSFlags(rawValue: 1 << 1) // kSecCSSigningInformation
        guard SecCodeCopySigningInformation(staticCode, flags, &unmanagedInformation) == errSecSuccess,
              let information = unmanagedInformation as? [String: Any],
              information[kSecCodeInfoIdentifier as String] as? String == "com.betacat.batteryforge",
              information[kSecCodeInfoTeamIdentifier as String] as? String == "TRM3RPP378",
              let cms = information[kSecCodeInfoCMS as String] as? Data,
              !cms.isEmpty
        else { return false }
        return true
    }
}

private enum SignalStorage {
    static var sources: [DispatchSourceSignal] = []
}

private enum SleepPolicy {
    static func isSleepDisabled() -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    static func setSleepDisabled(_ disabled: Bool) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["disablesleep", disabled ? "1" : "0"]
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SleepPolicyError.commandFailed(detail?.isEmpty == false ? detail! : "pmset 返回错误")
        }
    }
}

private enum SleepPolicyError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail): "无法阻止盒盖睡眠：\(detail)"
        }
    }
}

private final class HelperStressWorker {
    private var workers: [Task<Void, Never>] = []
    private var activity: NSObjectProtocol?
    private let gpuWorker = HelperGPUWorker()
    var isRunning: Bool { !workers.isEmpty }
    var isGPURunning: Bool { gpuWorker.isRunning }
    private(set) var workerCount = 0

    func start(workerCount requestedCount: Int, gpuEnabled: Bool) {
        let count = min(max(requestedCount, 1), ProcessInfo.processInfo.activeProcessorCount)
        if !isRunning || workerCount != count {
            stopCPU()
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "电池循环高负载任务"
            )
            workerCount = count
            workers = (0..<count).map { seed in
                Task.detached(priority: .background) {
                    var value = Double(seed + 1)
                    while !Task.isCancelled {
                        for _ in 0..<100_000 {
                            value = sin(value) * cos(value + 0.5) + 1.000_001
                        }
                        if !value.isFinite { value = Double(seed + 1) }
                        await Task.yield()
                    }
                }
            }
        }
        if gpuEnabled {
            gpuWorker.start()
        } else {
            gpuWorker.stop()
        }
    }

    func stop() {
        stopCPU()
        gpuWorker.stop()
    }

    private func stopCPU() {
        workers.forEach { $0.cancel() }
        workers.removeAll()
        workerCount = 0
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
}

private final class HelperGPUWorker {
    private var task: Task<Void, Never>?
    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil,
              let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else { return }

        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let function = library.makeFunction(name: "battery_gpu_burn"),
                  let pipeline = try? device.makeComputePipelineState(function: function)
            else { return }

            let elementCount = 262_144
            let byteCount = elementCount * MemoryLayout<SIMD4<Float>>.stride
            guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared)
            else { return }

            let values = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: elementCount)
            for index in 0..<elementCount {
                let seed = Float(index % 997) / 997.0 + 0.001
                values[index] = SIMD4(seed, seed + 0.1, seed + 0.2, seed + 0.3)
            }

            task = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    autoreleasepool {
                        guard let commandBuffer = commandQueue.makeCommandBuffer(),
                              let encoder = commandBuffer.makeComputeCommandEncoder()
                        else { return }

                        encoder.setComputePipelineState(pipeline)
                        encoder.setBuffer(buffer, offset: 0, index: 0)
                        let threadsPerGroup = MTLSize(
                            width: min(pipeline.maxTotalThreadsPerThreadgroup, 256),
                            height: 1,
                            depth: 1
                        )
                        encoder.dispatchThreads(
                            MTLSize(width: elementCount, height: 1, depth: 1),
                            threadsPerThreadgroup: threadsPerGroup
                        )
                        encoder.endEncoding()
                        commandBuffer.commit()
                        commandBuffer.waitUntilCompleted()
                    }
                    await Task.yield()
                }
            }
        } catch {
            NSLog("Battery helper could not start GPU workload: \(error)")
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void battery_gpu_burn(device float4 *values [[buffer(0)]],
                                 uint index [[thread_position_in_grid]]) {
        float4 value = values[index];
        for (uint iteration = 0; iteration < 128; ++iteration) {
            value = sin(value * 1.00013f + 0.17f)
                  + cos(value.yzwx * 0.99987f + 0.31f);
        }
        values[index] = value;
    }
    """
}
