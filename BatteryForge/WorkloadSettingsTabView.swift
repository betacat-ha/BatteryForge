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
                title: "高负载任务",
                subtitle: "设置放电阶段的 CPU 与 GPU 负载",
                updatedAt: updatedAt
            )
            workloadCard
        }
    }

    private var workloadCard: some View {
        GroupBox("计算负载") {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("在放电阶段运行高负载任务", isOn: $workloadEnabled)
                    .font(.headline)
                    .disabled(cycle.isRunning)
                Divider()
                LabeledContent("负载强度") {
                    Picker("负载强度", selection: $workloadLevelRaw) {
                        ForEach(WorkloadLevel.allCases) { level in
                            Text(level.title).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                    .disabled(!workloadEnabled || cycle.isRunning)
                }
                LabeledContent("CPU 工作线程") {
                    Text("\(stressWorkerCount) / \(processorCount)")
                        .monospacedDigit()
                }
                Label(workloadLevel.detail, systemImage: "cpu")
                    .foregroundStyle(.secondary)
                Divider()
                Toggle("同时运行 GPU 并行计算", isOn: $gpuLoadEnabled)
                    .disabled(!workloadEnabled || cycle.isRunning || gpuName == nil)
                LabeledContent("图形处理器") {
                    Text(gpuName ?? "未检测到支持 Metal 的 GPU")
                        .foregroundStyle(gpuName == nil ? .secondary : .primary)
                }
                Label("任务仅在放电阶段运行；开始充电、停止循环或温度过高时会自动停止", systemImage: "thermometer.medium")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if cycle.isRunning {
                    Label("循环运行期间不能修改负载设置", systemImage: "lock.fill")
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
