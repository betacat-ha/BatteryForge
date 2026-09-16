import Combine
import Foundation

enum CyclePhase: Equatable {
    case idle
    case preparing
    case charging
    case discharging
    case stopping
    case failed(String)

    var title: String {
        switch self {
        case .idle: AppLanguage.localized("cycle.phase.idle")
        case .preparing: AppLanguage.localized("cycle.phase.preparing")
        case .charging: AppLanguage.localized("cycle.phase.charging")
        case .discharging: AppLanguage.localized("cycle.phase.discharging")
        case .stopping: AppLanguage.localized("cycle.phase.stopping")
        case .failed: AppLanguage.localized("cycle.phase.failed")
        }
    }

    var symbol: String {
        switch self {
        case .idle: "pause.circle"
        case .preparing, .stopping: "gearshape.2"
        case .charging: "bolt.circle.fill"
        case .discharging: "flame.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class CycleController: ObservableObject {
    @Published private(set) var phase: CyclePhase = .idle
    @Published private(set) var completedCycles = 0
    @Published private(set) var statusMessage = AppLanguage.localized("cycle.status.ready")
    @Published private(set) var stressRunning = false
    @Published var showsHelperOnboarding = false

    let helper = HelperManager()

    var isRunning: Bool {
        switch phase {
        case .idle, .failed: false
        default: true
        }
    }

    var canStopCycle: Bool {
        isRunning || helper.isCycleRunning
    }

    private var pollingTimer: AnyCancellable?

    init(monitor: BatteryMonitor) {
        pollingTimer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.synchronizeWithHelper() }
        synchronizeWithHelper()
    }

    func start(
        lower: Int,
        upper: Int,
        useStress: Bool,
        stressWorkers: Int,
        useGPU: Bool,
        thermalProtectionEnabled: Bool,
        thermalThreshold: Double
    ) {
        guard !isRunning else { return }
        guard lower >= 10, upper <= 100, upper - lower >= 10 else {
            phase = .failed(
                String.localizedStringWithFormat(
                    AppLanguage.localized("cycle.error.threshold_gap"),
                    AppLanguage.localizedPercent(10)
                )
            )
            statusMessage = AppLanguage.localized("cycle.status.adjust_thresholds")
            return
        }
        helper.refreshRegistrationState()
        guard helper.state == .enabled else {
            showsHelperOnboarding = true
            phase = .failed(AppLanguage.localized("helper.error.approval_required"))
            statusMessage = AppLanguage.localized("helper.status.approve_then_retry")
            return
        }
        guard !helper.requiresUpdate else {
            let updateMessage = helper.updateDescription ?? AppLanguage.localized("helper.update.available")
            phase = .failed(updateMessage)
            statusMessage = updateMessage
            return
        }

        phase = .preparing
        statusMessage = AppLanguage.localized("cycle.status.handing_to_helper")
        helper.startCycle(
            lower: lower,
            upper: upper,
            highLoad: useStress,
            stressWorkers: stressWorkers,
            gpuLoad: useGPU,
            thermalProtectionEnabled: thermalProtectionEnabled,
            thermalThreshold: thermalThreshold
        ) { [weak self] result in
            switch result {
            case .success: self?.synchronizeWithHelper()
            case .failure(let error):
                self?.phase = .failed(error.localizedDescription)
                self?.statusMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        guard canStopCycle else {
            if case .failed = phase {
                phase = .idle
                statusMessage = AppLanguage.localized("cycle.status.ready")
            }
            return
        }
        phase = .stopping
        statusMessage = AppLanguage.localized("cycle.status.restoring_power")
        helper.stopCycle { [weak self] result in
            switch result {
            case .success:
                self?.phase = .idle
                self?.statusMessage = AppLanguage.localized("cycle.status.stopped_safely")
                self?.stressRunning = false
            case .failure(let error):
                self?.phase = .failed(error.localizedDescription)
                self?.statusMessage = error.localizedDescription
            }
        }
    }

    func installHelper() {
        // An outdated helper stays read-only while a cycle is active. The user
        // must explicitly stop that cycle before replacing the helper.
        guard !helper.requiresUpdate || !canStopCycle else { return }
        helper.install()
        synchronizeWithHelper()
    }

    func uninstallHelper() {
        guard !canStopCycle else { return }
        helper.uninstall()
    }

    func refreshLocalization() {
        if phase == .idle {
            statusMessage = AppLanguage.localized("cycle.status.ready")
        }
        synchronizeWithHelper()
    }

    func synchronizeWithHelper() {
        helper.refreshRegistrationState()
        guard helper.state == .enabled else { return }
        helper.refreshStatus { [weak self] in
            self?.applyHelperStatus()
        }
    }

    private func applyHelperStatus() {
        completedCycles = helper.completedCycles
        stressRunning = helper.highLoadRunning
        if phase != .stopping {
            statusMessage = helper.message.isEmpty ? statusMessage : helper.message
        }
        guard helper.isCycleRunning else {
            if phase != .preparing && phase != .stopping {
                phase = helper.phase == "failed" ? .failed(helper.message) : .idle
            }
            return
        }
        // A status response issued before Stop was clicked may still describe
        // discharging. Keep the local stopping state until Stop replies.
        if phase == .stopping { return }
        switch helper.phase {
        case "charging": phase = .charging
        case "discharging": phase = .discharging
        case "preparing": phase = .preparing
        case "stopping": phase = .stopping
        case "failed": phase = .failed(helper.message)
        default: break
        }
    }
}
