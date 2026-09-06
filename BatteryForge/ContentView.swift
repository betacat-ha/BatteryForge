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
    @AppStorage("cycle.lowerLimit") private var lowerLimit = 25.0
    @AppStorage("cycle.upperLimit") private var upperLimit = 80.0
    @AppStorage("workload.enabled") private var workloadEnabled = true
    @AppStorage("workload.level") private var workloadLevelRaw = WorkloadLevel.balanced.rawValue
    @AppStorage("workload.gpuEnabled") private var gpuLoadEnabled = true
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    init(monitor: BatteryMonitor? = nil) {
        let batteryMonitor = monitor ?? BatteryMonitor()
        _monitor = StateObject(wrappedValue: batteryMonitor)
        _cycle = StateObject(wrappedValue: CycleController(monitor: batteryMonitor))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Label("sidebar.overview", systemImage: "gauge.with.dots.needle.50percent")
                    .tag(SidebarPage.overview)
                Label("sidebar.cycle", systemImage: "arrow.triangle.2.circlepath")
                    .tag(SidebarPage.cycle)
                Label("sidebar.workload", systemImage: "cpu")
                    .tag(SidebarPage.workload)
                Label("sidebar.history", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarPage.history)
                Divider()
                Label("sidebar.settings", systemImage: "gearshape")
                    .tag(SidebarPage.settings)
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
                        Label("common.refresh", systemImage: "arrow.clockwise")
                    }
                    .help("common.refresh_battery")
                }
            }
        }
        .frame(minWidth: 900, minHeight: 680)
        .environment(\.locale, appLanguage.locale)
        .onAppear(perform: normalizeSavedSettings)
        .onChange(of: lowerLimit) { _, newValue in
            upperLimit = max(upperLimit, newValue + 10)
        }
        .onChange(of: appLanguageRawValue) { _, _ in
            monitor.refresh()
            cycle.refreshLocalization()
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
        case .settings:
            SettingsTabView(languageRawValue: $appLanguageRawValue)
        }
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private func normalizeSavedSettings() {
        if !lowerLimit.isFinite { lowerLimit = 25 }
        if !upperLimit.isFinite { upperLimit = 80 }
        lowerLimit = min(max(lowerLimit, 10), 70)
        upperLimit = min(max(upperLimit, lowerLimit + 10), 100)
        if WorkloadLevel(rawValue: workloadLevelRaw) == nil {
            workloadLevelRaw = WorkloadLevel.balanced.rawValue
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
        let format = effectiveGPULoadEnabled
            ? String(localized: "workload.summary.cpu_gpu", locale: AppLanguage.currentLocale)
            : String(localized: "workload.summary.cpu", locale: AppLanguage.currentLocale)
        return String.localizedStringWithFormat(format, workloadLevel.title, stressWorkerCount)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(monitor: BatteryMonitor(startMonitoring: false, initialSnapshot: .preview))
    }
}
