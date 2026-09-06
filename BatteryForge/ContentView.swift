//
//  ContentView.swift
//  battery
//
//  Created by BetaCat on 5/9/26.
//

import Metal
import SwiftUI

struct ContentView: View {
    @StateObject private var monitor: BatteryMonitor
    @StateObject private var cycle: CycleController
    @State private var selectedPage: SidebarPage? = .overview
    @State private var lowerLimit = 25.0
    @State private var upperLimit = 80.0
    @AppStorage("workload.enabled") private var workloadEnabled = true
    @AppStorage("workload.level") private var workloadLevelRaw = WorkloadLevel.balanced.rawValue
    @AppStorage("workload.gpuEnabled") private var gpuLoadEnabled = true

    init(monitor: BatteryMonitor? = nil) {
        let batteryMonitor = monitor ?? BatteryMonitor()
        _monitor = StateObject(wrappedValue: batteryMonitor)
        _cycle = StateObject(wrappedValue: CycleController(monitor: batteryMonitor))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Label("概览", systemImage: "gauge.with.dots.needle.50percent")
                    .tag(SidebarPage.overview)
                Label("循环设置", systemImage: "arrow.triangle.2.circlepath")
                    .tag(SidebarPage.cycle)
                Label("高负载任务", systemImage: "cpu")
                    .tag(SidebarPage.workload)
                Label("运行记录", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarPage.history)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ScrollView {
                selectedTab
                    .padding(28)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .toolbar {
                ToolbarItem {
                    Button(action: monitor.refresh) {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .help("刷新电池数据")
                }
            }
        }
        .frame(minWidth: 900, minHeight: 680)
        .onChange(of: lowerLimit) { _, newValue in
            upperLimit = max(upperLimit, newValue + 10)
        }
    }

    @ViewBuilder
    private var selectedTab: some View {
        switch selectedPage ?? .overview {
        case .overview:
            OverviewTabView(monitor: monitor)
        case .cycle:
            CycleSettingsTabView(
                monitor: monitor,
                cycle: cycle,
                helper: cycle.helper,
                lowerLimit: $lowerLimit,
                upperLimit: $upperLimit,
                workloadEnabled: workloadEnabled,
                workloadSummary: workloadSummary,
                stressWorkers: stressWorkerCount,
                gpuLoadEnabled: effectiveGPULoadEnabled,
                openWorkloadSettings: { selectedPage = .workload }
            )
        case .workload:
            WorkloadSettingsTabView(
                cycle: cycle,
                workloadEnabled: $workloadEnabled,
                workloadLevelRaw: $workloadLevelRaw,
                gpuLoadEnabled: $gpuLoadEnabled,
                updatedAt: monitor.snapshot.lastUpdated
            )
        case .history:
            HistoryTabView(updatedAt: monitor.snapshot.lastUpdated)
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

    private var effectiveGPULoadEnabled: Bool {
        gpuLoadEnabled && MTLCreateSystemDefaultDevice() != nil
    }

    private var workloadSummary: String {
        "\(workloadLevel.title) · \(stressWorkerCount) 个 CPU 线程\(effectiveGPULoadEnabled ? " + GPU" : "")"
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(monitor: BatteryMonitor(startMonitoring: false, initialSnapshot: .preview))
    }
}
