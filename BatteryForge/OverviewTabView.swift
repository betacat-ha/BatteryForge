import SwiftUI

struct OverviewTabView: View {
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject var cycle: CycleController
    let lowerLimit: Double
    let upperLimit: Double
    let workloadEnabled: Bool
    let workloadSummary: String
    let stressWorkers: Int
    let gpuLoadEnabled: Bool

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "overview.title",
                subtitle: "overview.subtitle",
                updatedAt: monitor.snapshot.lastUpdated
            )
            if monitor.hasBattery {
                batteryHero
                cycleControlCard
                metricsGrid
            } else {
                NoBatteryView()
            }
        }
    }

    private var cycleControlCard: some View {
        GroupBox("cycle.group.title") {
            VStack(spacing: 14) {
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
                                        String(localized: "cycle.completed_count", locale: AppLanguage.currentLocale),
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

                Divider()

                HStack(spacing: 24) {
                    LabeledContent("cycle.threshold.start_charging") {
                        Text(verbatim: "\(Int(lowerLimit))%")
                            .monospacedDigit()
                    }
                    LabeledContent("cycle.threshold.stop_charging") {
                        Text(verbatim: "\(Int(upperLimit))%")
                            .monospacedDigit()
                    }
                    LabeledContent("workload.title") {
                        Text(workloadEnabled ? workloadSummary : String(localized: "common.disabled", locale: AppLanguage.currentLocale))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

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
            .padding(8)
        }
    }

    private var batteryHero: some View {
        GroupBox {
            HStack(spacing: 26) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.14), lineWidth: 13)
                    Circle()
                        .trim(from: 0, to: CGFloat(monitor.snapshot.chargePercent) / 100)
                        .stroke(chargeColor, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(verbatim: "\(monitor.snapshot.chargePercent)%")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text("battery.charge_level")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: 12) {
                    Label(monitor.snapshot.stateDescription, systemImage: statusIcon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(chargeColor)
                    if let batteryName = monitor.snapshot.batteryName {
                        Text(batteryName).foregroundStyle(.secondary)
                    } else {
                        Text("battery.internal").foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack(spacing: 28) {
                        HeroValue(title: "battery.time_remaining", value: timeDescription)
                        HeroValue(title: "battery.power", value: powerDescription)
                        HeroValue(title: "battery.health.calculated", value: batteryHealthDescription)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
            MetricCard(title: "battery.voltage", value: millivoltDescription, detail: String(localized: "battery.voltage.detail", locale: AppLanguage.currentLocale), icon: "bolt.fill", tint: .yellow)
            MetricCard(title: "battery.current", value: currentDescription, detail: currentFlowDetail, icon: "waveform.path.ecg", tint: .blue)
            MetricCard(title: "battery.capacity.maximum", value: capacityDescription(monitor.snapshot.maximumCapacity), detail: healthDetail, icon: "battery.75percent", tint: .green)
            MetricCard(title: "battery.health.system", value: systemBatteryHealthDescription, detail: String(localized: "battery.health.system.source", locale: AppLanguage.currentLocale), icon: "checkmark.shield.fill", tint: .mint)
            MetricCard(title: "battery.capacity.design", value: capacityDescription(monitor.snapshot.designCapacity), detail: String(localized: "battery.capacity.design.detail", locale: AppLanguage.currentLocale), icon: "ruler", tint: .indigo)
            MetricCard(title: "battery.cycle_count", value: monitor.snapshot.cycleCount.map(String.init) ?? "—", detail: String(localized: "battery.cycle_count.detail", locale: AppLanguage.currentLocale), icon: "repeat", tint: .orange)
            MetricCard(title: "battery.temperature", value: monitor.snapshot.temperature.map { String(format: "%.1f °C", $0) } ?? "—", detail: temperatureDetail, icon: "thermometer.medium", tint: .red)
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

    private var chargeColor: Color {
        if monitor.snapshot.isCharging { return .green }
        if monitor.snapshot.chargePercent <= 20 { return .red }
        return .accentColor
    }

    private var statusIcon: String {
        if monitor.snapshot.isCharging { return "bolt.fill" }
        if monitor.snapshot.isConnectedToAC { return "powerplug.fill" }
        return "battery.75percent"
    }

    private var timeDescription: String {
        guard let minutes = monitor.snapshot.timeRemaining else {
            return String(localized: "battery.time.calculating", locale: AppLanguage.currentLocale)
        }
        return String.localizedStringWithFormat(
            String(localized: "battery.time.hours_minutes", locale: AppLanguage.currentLocale),
            minutes / 60,
            minutes % 60
        )
    }

    private var powerDescription: String {
        guard let power = monitor.snapshot.power else { return "—" }
        return String(format: "%.1f W", abs(power))
    }

    private var millivoltDescription: String {
        monitor.snapshot.voltage.map { String(format: "%.2f V", Double($0) / 1_000) } ?? "—"
    }

    private var currentDescription: String {
        monitor.snapshot.amperage.map { String(format: "%+.2f A", Double($0) / 1_000) } ?? "—"
    }

    private func capacityDescription(_ value: Int?) -> String {
        value.map { "\($0.formatted()) mAh" } ?? "—"
    }

    private var currentFlowDetail: String {
        guard let amperage = monitor.snapshot.amperage else { return String(localized: "common.no_data", locale: AppLanguage.currentLocale) }
        return amperage >= 0
            ? String(localized: "battery.flow.charging", locale: AppLanguage.currentLocale)
            : String(localized: "battery.flow.discharging", locale: AppLanguage.currentLocale)
    }

    private var healthDetail: String {
        guard let condition = monitor.snapshot.healthCondition else {
            return String(localized: "battery.capacity.current_full", locale: AppLanguage.currentLocale)
        }
        return String.localizedStringWithFormat(
            String(localized: "battery.health.system_status", locale: AppLanguage.currentLocale),
            condition
        )
    }

    private var batteryHealthDescription: String {
        monitor.snapshot.healthPercent.map { "\($0)%" } ?? "—"
    }

    private var systemBatteryHealthDescription: String {
        monitor.snapshot.systemHealthPercent.map { "\($0)%" }
            ?? String(localized: "common.loading", locale: AppLanguage.currentLocale)
    }

    private var temperatureDetail: String {
        guard let temperature = monitor.snapshot.temperature else { return String(localized: "common.no_data", locale: AppLanguage.currentLocale) }
        return temperature < 40
            ? String(localized: "battery.temperature.normal", locale: AppLanguage.currentLocale)
            : String(localized: "battery.temperature.high", locale: AppLanguage.currentLocale)
    }
}
