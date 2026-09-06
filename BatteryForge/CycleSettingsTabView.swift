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
                title: "cycle.title",
                subtitle: "cycle.subtitle",
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
        GroupBox("cycle.group.title") {
            VStack(spacing: 14) {
                cycleStatus
                Divider()
                helperStatus
                thresholdControls
                workloadRow
                Label("cycle.sleep_prevention.note", systemImage: "moon.zzz")
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
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "cycle.completed_count"),
                                cycle.completedCycles
                            )
                        )
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
                Button("helper.action.install") { cycle.installHelper() }
            case .installing:
                ProgressView().controlSize(.small)
            case .enabled:
                HStack(spacing: 10) {
                    Text("helper.authorization.once")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(helperUpdateTitle) {
                        cycle.installHelper()
                    }
                        .controlSize(.small)
                }
            }
        }
    }

    private var thresholdControls: some View {
        Group {
            LabeledContent("cycle.threshold.start_charging") {
                HStack {
                    Slider(value: $lowerLimit, in: 10...70, step: 5)
                        .frame(width: 180)
                        .disabled(cycle.isRunning)
                    Text(verbatim: "\(Int(lowerLimit))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            LabeledContent("cycle.threshold.stop_charging") {
                HStack {
                    Slider(value: $upperLimit, in: max(lowerLimit + 10, 40)...100, step: 5)
                        .frame(width: 180)
                        .disabled(cycle.isRunning)
                    Text(verbatim: "\(Int(upperLimit))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var workloadRow: some View {
        LabeledContent("workload.title") {
            HStack(spacing: 8) {
                Text(workloadEnabled ? workloadSummary : String(localized: "common.disabled"))
                    .foregroundStyle(.secondary)
                Button("common.settings", action: openWorkloadSettings)
                    .controlSize(.small)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            Label("cycle.background_execution.note", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if cycle.isRunning {
                Button("cycle.action.stop", role: .destructive) {
                    cycle.stop()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("cycle.action.start") {
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

    private var helperUpdateTitle: String {
        cycle.isRunning
            ? String(localized: "helper.action.reinstall_and_stop")
            : String(localized: "helper.action.update")
    }
}
