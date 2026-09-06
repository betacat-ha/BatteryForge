import Metal
import SwiftUI

struct WorkloadSettingsTabView: View {
    @ObservedObject var cycle: CycleController
    @Binding var workloadEnabled: Bool
    @Binding var workloadLevelRaw: Int
    @Binding var gpuLoadEnabled: Bool
    let updatedAt: Date

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "workload.title",
                subtitle: "workload.subtitle",
                updatedAt: updatedAt
            )
            workloadCard
        }
    }

    private var workloadCard: some View {
        GroupBox("workload.group.title") {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("workload.enable_during_discharge", isOn: $workloadEnabled)
                    .font(.headline)
                    .disabled(cycle.isRunning)
                Divider()
                LabeledContent("workload.intensity") {
                    Picker("workload.intensity", selection: $workloadLevelRaw) {
                        ForEach(WorkloadLevel.allCases) { level in
                            Text(level.title).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                    .disabled(!workloadEnabled || cycle.isRunning)
                }
                LabeledContent("workload.cpu_workers") {
                    Text(verbatim: "\(stressWorkerCount) / \(processorCount)")
                        .monospacedDigit()
                }
                Label(workloadLevel.detail, systemImage: "cpu")
                    .foregroundStyle(.secondary)
                Divider()
                Toggle("workload.gpu.enable", isOn: $gpuLoadEnabled)
                    .disabled(!workloadEnabled || cycle.isRunning || gpuName == nil)
                LabeledContent("workload.gpu") {
                    if let gpuName {
                        Text(gpuName)
                    } else {
                        Text("workload.gpu.unavailable")
                            .foregroundStyle(.secondary)
                    }
                }
                Label("workload.safety.note", systemImage: "thermometer.medium")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if cycle.isRunning {
                    Label("workload.locked_during_cycle", systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var workloadLevel: WorkloadLevel {
        WorkloadLevel(rawValue: workloadLevelRaw) ?? .balanced
    }

    private var processorCount: Int {
        max(ProcessInfo.processInfo.activeProcessorCount, 1)
    }

    private var stressWorkerCount: Int {
        workloadLevel.workerCount(processorCount: processorCount)
    }

    private var gpuName: String? {
        MTLCreateSystemDefaultDevice()?.name
    }
}
