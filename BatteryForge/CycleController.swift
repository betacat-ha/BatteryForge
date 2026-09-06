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
        case .idle: String(localized: "cycle.phase.idle", locale: AppLanguage.currentLocale)
        case .preparing: String(localized: "cycle.phase.preparing", locale: AppLanguage.currentLocale)
        case .charging: String(localized: "cycle.phase.charging", locale: AppLanguage.currentLocale)
        case .discharging: String(localized: "cycle.phase.discharging", locale: AppLanguage.currentLocale)
        case .stopping: String(localized: "cycle.phase.stopping", locale: AppLanguage.currentLocale)
        case .failed: String(localized: "cycle.phase.failed", locale: AppLanguage.currentLocale)
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
    @Published private(set) var statusMessage = String(localized: "cycle.status.ready", locale: AppLanguage.currentLocale)
    @Published private(set) var stressRunning = false

    let helper = HelperManager()

    var isRunning: Bool {
        switch phase {
        case .idle, .failed: false
        default: true
        }
    }

    private var pollingTimer: AnyCancellable?

    init(monitor: BatteryMonitor) {
        pollingTimer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.synchronizeWithHelper() }
        synchronizeWithHelper()
    }

    func start(lower: Int, upper: Int, useStress: Bool, stressWorkers: Int, useGPU: Bool) {
        guard !isRunning else { return }
        guard lower >= 10, upper <= 100, upper - lower >= 10 else {
            phase = .failed(String(localized: "cycle.error.threshold_gap", locale: AppLanguage.currentLocale))
            statusMessage = String(localized: "cycle.status.adjust_thresholds", locale: AppLanguage.currentLocale)
            return
        }
        guard helper.state == .enabled else {
            helper.install()
            phase = .failed(String(localized: "helper.error.approval_required", locale: AppLanguage.currentLocale))
            statusMessage = helper.message.isEmpty ? String(localized: "helper.status.approve_then_retry", locale: AppLanguage.currentLocale) : helper.message
            return
        }

        phase = .preparing
        statusMessage = String(localized: "cycle.status.handing_to_helper", locale: AppLanguage.currentLocale)
        helper.startCycle(
            lower: lower,
            upper: upper,
            highLoad: useStress,
            stressWorkers: stressWorkers,
            gpuLoad: useGPU
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
        guard isRunning || helper.isCycleRunning else {
            if case .failed = phase {
                phase = .idle
                statusMessage = String(localized: "cycle.status.ready", locale: AppLanguage.currentLocale)
            }
            return
        }
        phase = .stopping
        statusMessage = String(localized: "cycle.status.restoring_power", locale: AppLanguage.currentLocale)
        helper.stopCycle { [weak self] result in
            switch result {
            case .success:
                self?.phase = .idle
                self?.statusMessage = String(localized: "cycle.status.stopped_safely", locale: AppLanguage.currentLocale)
                self?.stressRunning = false
            case .failure(let error):
                self?.phase = .failed(error.localizedDescription)
                self?.statusMessage = error.localizedDescription
            }
        }
    }

    func installHelper() {
        helper.install()
        synchronizeWithHelper()
    }

    func refreshLocalization() {
        if phase == .idle {
            statusMessage = String(localized: "cycle.status.ready", locale: AppLanguage.currentLocale)
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
