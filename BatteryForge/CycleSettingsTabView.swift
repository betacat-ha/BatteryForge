import SwiftUI

struct CycleSettingsTabView: View {
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject var cycle: CycleController
    @ObservedObject var helper: HelperManager
    @Binding var lowerLimit: Double
    @Binding var upperLimit: Double
    let workloadEnabled: Bool
    let workloadSummary: String
    let stressWorkers: Int
    let gpuLoadEnabled: Bool
    let openWorkloadSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "循环设置",
                subtitle: "配置自动充电与放电阈值",
                updatedAt: monitor.snapshot.lastUpdated
            )
            if monitor.hasBattery {
                automationCard
            } else {
                NoBatteryView()
            }
        }
    }

    private var automationCard: some View {
        GroupBox("充放电循环") {
            VStack(spacing: 14) {
                cycleStatus
                Divider()
                helperStatus
                thresholdControls
                workloadRow
                Label("放电阶段会阻止系统睡眠（包括合盖睡眠），恢复充电或停止循环后自动还原", systemImage: "moon.zzz")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                actionRow
            }
            .padding(8)
        }
    }

    private var cycleStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: cycle.phase.symbol)
                .font(.title2)
                .foregroundStyle(cyclePhaseColor)
                .symbolEffect(.pulse, isActive: cycle.isRunning)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(cycle.phase.title).font(.headline)
                    if cycle.completedCycles > 0 {
                        Text("已完成 \(cycle.completedCycles) 次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(cycle.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var helperStatus: some View {
        HStack {
            Label(helper.state.title, systemImage: helperStateIcon)
                .foregroundStyle(helperStateColor)
            Spacer()
            switch helper.state {
            case .notRegistered, .unavailable:
                Button("安装后台服务") { cycle.installHelper() }
            case .installing:
                ProgressView().controlSize(.small)
            case .enabled:
                HStack(spacing: 10) {
                    Text("运行时无需再次授权")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("更新后台服务") { cycle.installHelper() }
                        .controlSize(.small)
                        .disabled(cycle.isRunning)
                }
            }
        }
    }

    private var thresholdControls: some View {
        Group {
            LabeledContent("开始充电") {
                HStack {
                    Slider(value: $lowerLimit, in: 10...70, step: 5)
                        .frame(width: 180)
                        .disabled(cycle.isRunning)
                    Text("\(Int(lowerLimit))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            LabeledContent("停止充电并切换电池") {
                HStack {
                    Slider(value: $upperLimit, in: max(lowerLimit + 10, 40)...100, step: 5)
                        .frame(width: 180)
                        .disabled(cycle.isRunning)
                    Text("\(Int(upperLimit))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var workloadRow: some View {
        LabeledContent("高负载任务") {
            HStack(spacing: 8) {
                Text(workloadEnabled ? workloadSummary : "已关闭")
                    .foregroundStyle(.secondary)
                Button("设置", action: openWorkloadSettings)
                    .controlSize(.small)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            Label("循环由后台服务执行，关闭主窗口或退出应用后仍会继续", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if cycle.isRunning {
                Button("停止循环", role: .destructive) {
                    cycle.stop()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("开始循环") {
                    cycle.start(
                        lower: Int(lowerLimit),
                        upper: Int(upperLimit),
                        useStress: workloadEnabled,
                        stressWorkers: stressWorkers,
                        useGPU: gpuLoadEnabled
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var cyclePhaseColor: Color {
        switch cycle.phase {
        case .idle: .secondary
        case .preparing, .stopping: .orange
        case .charging: .green
        case .discharging, .failed: .red
        }
    }

    private var helperStateColor: Color {
        helper.state == .enabled ? .green : .orange
    }

    private var helperStateIcon: String {
        helper.state == .enabled ? "checkmark.circle.fill" : "exclamationmark.circle"
    }
}
