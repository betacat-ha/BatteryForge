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
        case .idle: "未运行"
        case .preparing: "正在准备"
        case .charging: "充电至上限"
        case .discharging: "放电至下限"
        case .stopping: "正在安全停止"
        case .failed: "循环已停止"
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
    @Published private(set) var statusMessage = "设置阈值后即可开始"
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
            phase = .failed("上下限至少需要相差 10%")
            statusMessage = "请调整充放电阈值"
            return
        }
        guard helper.state == .enabled else {
            helper.install()
            phase = .failed("需要先批准后台服务")
            statusMessage = helper.message.isEmpty ? "批准后台服务后再次点击开始" : helper.message
            return
        }

        phase = .preparing
        statusMessage = "正在将循环任务交给后台服务"
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
            if case .failed = phase { phase = .idle; statusMessage = "设置阈值后即可开始" }
            return
        }
        phase = .stopping
        statusMessage = "后台服务正在恢复 AC 供电和正常充电"
        helper.stopCycle { [weak self] result in
            switch result {
            case .success:
                self?.phase = .idle
                self?.statusMessage = "已安全停止"
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
