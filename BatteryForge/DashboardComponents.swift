import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String
    let updatedAt: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("更新于 \(updatedAt, format: .dateTime.hour().minute().second())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct NoBatteryView: View {
    var body: some View {
        ContentUnavailableView(
            "未检测到电池",
            systemImage: "battery.0percent",
            description: Text("此 Mac 可能没有内置电池，或系统暂时无法读取电池信息。")
        )
        .frame(minHeight: 360)
    }
}

struct HeroValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .font(.title3)
                    Spacer()
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(5)
        }
    }
}
