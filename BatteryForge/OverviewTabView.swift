import SwiftUI

struct OverviewTabView: View {
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "电池概览",
                subtitle: "实时电池状态与健康信息",
                updatedAt: monitor.snapshot.lastUpdated
            )
            if monitor.hasBattery {
                batteryHero
                metricsGrid
            } else {
                NoBatteryView()
            }
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
                        Text("\(monitor.snapshot.chargePercent)%")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text("电量")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: 12) {
                    Label(monitor.snapshot.stateDescription, systemImage: statusIcon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(chargeColor)
                    Text(monitor.snapshot.batteryName ?? "内置电池")
                        .foregroundStyle(.secondary)
                    Divider()
                    HStack(spacing: 28) {
                        HeroValue(title: "预计剩余", value: timeDescription)
                        HeroValue(title: "实时功率", value: powerDescription)
                        HeroValue(title: "容量健康（计算）", value: batteryHealthDescription)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
            MetricCard(title: "电池电压", value: millivoltDescription, detail: "当前端电压", icon: "bolt.fill", tint: .yellow)
            MetricCard(title: "电池电流", value: currentDescription, detail: monitor.snapshot.amperage.map { $0 >= 0 ? "流入电池" : "由电池输出" } ?? "暂无数据", icon: "waveform.path.ecg", tint: .blue)
            MetricCard(title: "最大容量", value: capacityDescription(monitor.snapshot.maximumCapacity), detail: healthDetail, icon: "battery.75percent", tint: .green)
            MetricCard(title: "系统电池健康", value: systemBatteryHealthDescription, detail: "从 macOS 系统信息读取", icon: "checkmark.shield.fill", tint: .mint)
            MetricCard(title: "设计容量", value: capacityDescription(monitor.snapshot.designCapacity), detail: "出厂标称容量", icon: "ruler", tint: .indigo)
            MetricCard(title: "循环次数", value: monitor.snapshot.cycleCount.map(String.init) ?? "—", detail: "完整充放电循环", icon: "repeat", tint: .orange)
            MetricCard(title: "电池温度", value: monitor.snapshot.temperature.map { String(format: "%.1f °C", $0) } ?? "—", detail: temperatureDetail, icon: "thermometer.medium", tint: .red)
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
        guard let minutes = monitor.snapshot.timeRemaining else { return "正在计算" }
        return "\(minutes / 60)小时 \(minutes % 60)分钟"
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

    private var healthDetail: String {
        monitor.snapshot.healthCondition.map { "系统状态：\($0)" } ?? "当前满充容量"
    }

    private var batteryHealthDescription: String {
        monitor.snapshot.healthPercent.map { "\($0)%" } ?? "—"
    }

    private var systemBatteryHealthDescription: String {
        monitor.snapshot.systemHealthPercent.map { "\($0)%" } ?? "读取中…"
    }

    private var temperatureDetail: String {
        guard let temperature = monitor.snapshot.temperature else { return "暂无数据" }
        return temperature < 40 ? "温度正常" : "温度偏高"
    }
}
