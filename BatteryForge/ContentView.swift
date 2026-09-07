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
    @ObservedObject private var updateManager: AppUpdateManager
    @State private var selectedPage: SidebarPage? = .overview
    @AppStorage("cycle.lowerLimit") private var lowerLimit = 25.0
    @AppStorage("cycle.upperLimit") private var upperLimit = 80.0
    @AppStorage("workload.enabled") private var workloadEnabled = true
    @AppStorage("workload.level") private var workloadLevelRaw = WorkloadLevel.balanced.rawValue
    @AppStorage("workload.gpuEnabled") private var gpuLoadEnabled = true
    @AppStorage("workload.thermalProtectionEnabled") private var thermalProtectionEnabled = true
    @AppStorage("workload.thermalThreshold") private var thermalThreshold = 45.0
    @AppStorage(AppLanguage.storageKey) private var appLanguageRawValue = AppLanguage.system.rawValue

    init(monitor: BatteryMonitor? = nil, updateManager: AppUpdateManager? = nil) {
        let batteryMonitor = monitor ?? BatteryMonitor()
        _monitor = StateObject(wrappedValue: batteryMonitor)
        _cycle = StateObject(wrappedValue: CycleController(monitor: batteryMonitor))
        self.updateManager = updateManager ?? AppUpdateManager()
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Label("sidebar.overview", systemImage: "gauge.with.dots.needle.50percent")
                    .tag(SidebarPage.overview)
                Label("sidebar.history", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarPage.history)
                Divider()
                Label("sidebar.settings", systemImage: "gearshape")
                    .tag(SidebarPage.settings)
                Label("sidebar.about", systemImage: "info.circle")
                    .tag(SidebarPage.about)
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
        .task { await updateManager.checkAutomaticallyIfNeeded() }
        .alert(updateManager.alertTitle, isPresented: $updateManager.isUpdateAlertPresented) {
            if case .updateAvailable = updateManager.state {
                Button("app_update.download") { updateManager.openUpdate() }
                Button("app_update.later", role: .cancel) {}
            } else {
                Button("common.ok", role: .cancel) {}
            }
        } message: {
            Text(updateManager.alertMessage)
        }
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
            OverviewTabView(
                monitor: monitor,
                cycle: cycle,
                lowerLimit: lowerLimit,
                upperLimit: upperLimit,
                workloadEnabled: workloadEnabled,
                stressWorkers: stressWorkerCount,
                gpuLoadEnabled: effectiveGPULoadEnabled,
                thermalProtectionEnabled: thermalProtectionEnabled,
                thermalThreshold: thermalThreshold
            )
        case .history:
            HistoryTabView(helper: cycle.helper)
        case .settings:
            SettingsTabView(
                cycle: cycle,
                helper: cycle.helper,
                updateManager: updateManager,
                lowerLimit: $lowerLimit,
                upperLimit: $upperLimit,
                workloadEnabled: $workloadEnabled,
                workloadLevelRaw: $workloadLevelRaw,
                gpuLoadEnabled: $gpuLoadEnabled,
                thermalProtectionEnabled: $thermalProtectionEnabled,
                thermalThreshold: $thermalThreshold,
                languageRawValue: $appLanguageRawValue
            )
        case .about:
            AboutTabView(updateManager: updateManager)
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
        if !thermalThreshold.isFinite { thermalThreshold = 45 }
        thermalThreshold = min(max(thermalThreshold, 35), 60)
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

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(monitor: BatteryMonitor(startMonitoring: false, initialSnapshot: .preview))
    }
}
