import Metal
import SwiftUI

struct WorkloadSettingsTabView: View {
    @ObservedObject var cycle: CycleController
    @ObservedObject var helper: HelperManager
    @Binding var workloadEnabled: Bool
    @Binding var workloadLevelRaw: Int
    @Binding var gpuLoadEnabled: Bool
    @Binding var thermalProtectionEnabled: Bool
    @Binding var thermalThreshold: Double

    var body: some View {
        workloadCard
    }

    private var workloadCard: some View {
        GroupBox("workload.group.title") {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("workload.enable_during_discharge", isOn: $workloadEnabled)
                    .font(.headline)
                    .disabled(controlsAreLocked)
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
                    .disabled(!workloadEnabled || controlsAreLocked)
                }
                LabeledContent("workload.cpu_workers") {
                    Text(verbatim: "\(stressWorkerCount) / \(processorCount)")
                        .monospacedDigit()
                }
                Label(workloadLevel.detail, systemImage: "cpu")
                    .foregroundStyle(.secondary)
                Divider()
                Toggle("workload.gpu.enable", isOn: $gpuLoadEnabled)
                    .disabled(!workloadEnabled || controlsAreLocked || gpuName == nil)
                LabeledContent("workload.gpu") {
                    if let gpuName {
                        Text(gpuName)
                    } else {
                        Text("workload.gpu.unavailable")
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle("workload.thermal_protection.enable", isOn: $thermalProtectionEnabled)
                    .disabled(!workloadEnabled || controlsAreLocked)
                LabeledContent("workload.thermal_protection.threshold") {
                    Stepper(value: $thermalThreshold, in: 35...60, step: 1) {
                        Text(verbatim: "\(Int(thermalThreshold)) °C")
                            .monospacedDigit()
                    }
                    .disabled(!workloadEnabled || !thermalProtectionEnabled || controlsAreLocked)
                }
                Label("workload.safety.note", systemImage: "thermometer.medium")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if cycle.canStopCycle {
                    Label("workload.locked_during_cycle", systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if helper.requiresUpdate {
                    Label("helper.update.read_only", systemImage: "lock.fill")
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

    private var controlsAreLocked: Bool {
        cycle.canStopCycle || helper.requiresUpdate
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
