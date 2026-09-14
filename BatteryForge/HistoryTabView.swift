import SwiftUI

struct HistoryTabView: View {
    @ObservedObject var helper: HelperManager
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "history.title",
                subtitle: "history.subtitle",
                updatedAt: helper.historyUpdatedAt
            )
            historyToolbar
            if let error = helper.historyError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            historyContent
        }
        .onAppear(perform: helper.refreshHistory)
        .onChange(of: helper.phase) { _, _ in helper.refreshHistory() }
        .onChange(of: helper.completedCycles) { _, _ in helper.refreshHistory() }
        .confirmationDialog(
            "history.clear.confirm.title",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("history.action.clear", role: .destructive, action: helper.clearHistory)
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("history.clear.confirm.message")
        }
    }

    private var historyToolbar: some View {
        HStack {
            Label(eventCountDescription, systemImage: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
            Spacer()
            Button("history.action.refresh", systemImage: "arrow.clockwise") {
                helper.refreshHistory()
            }
            .disabled(helper.isHistoryLoading || helper.requiresUpdate)
            Button("history.action.clear", systemImage: "trash", role: .destructive) {
                showsClearConfirmation = true
            }
            .disabled(helper.historyEntries.isEmpty || helper.isHistoryLoading || helper.requiresUpdate)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if helper.requiresUpdate {
            ContentUnavailableView(
                "history.update_required.title",
                systemImage: "arrow.triangle.2.circlepath.circle.fill",
                description: Text("history.update_required.description")
            )
            .frame(minHeight: 360)
        } else if helper.isHistoryLoading && helper.historyEntries.isEmpty {
            ProgressView("history.loading")
                .frame(maxWidth: .infinity, minHeight: 360)
        } else if helper.historyEntries.isEmpty {
            ContentUnavailableView(
                "history.empty.title",
                systemImage: "clock.arrow.circlepath",
                description: Text("history.empty.description")
            )
            .frame(minHeight: 360)
        } else {
            GroupBox {
                LazyVStack(spacing: 0) {
                    ForEach(Array(helper.historyEntries.enumerated()), id: \.element.id) { index, entry in
                        HistoryEntryRow(entry: entry)
                        if index < helper.historyEntries.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private var eventCountDescription: String {
        String.localizedStringWithFormat(
            AppLanguage.localized("history.event_count"),
            helper.historyEntries.count
        )
    }
}

private struct HistoryEntryRow: View {
    let entry: CycleHistoryEntry

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(localizedHelperMessage(entry.message))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if entry.kind == "started" {
                    Text(configurationDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 4) {
                if let percent = entry.batteryPercent {
                    Text(verbatim: "\(percent)%")
                        .font(.headline)
                        .monospacedDigit()
                }
                Text(entry.timestamp.formatted(dateFormat))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }

    private var title: String {
        switch entry.kind {
        case "started": AppLanguage.localized("history.event.started")
        case "charging": AppLanguage.localized("history.event.charging")
        case "discharging": AppLanguage.localized("history.event.discharging")
        case "completed": AppLanguage.localized("history.event.completed")
        case "stopped": AppLanguage.localized("history.event.stopped")
        case "failed": AppLanguage.localized("history.event.failed")
        default: AppLanguage.localized("history.event.unknown")
        }
    }

    private var icon: String {
        switch entry.kind {
        case "started": "play.circle.fill"
        case "charging": "bolt.circle.fill"
        case "discharging": "flame.fill"
        case "completed": "checkmark.circle.fill"
        case "stopped": "stop.circle.fill"
        case "failed": "exclamationmark.triangle.fill"
        default: "clock.fill"
        }
    }

    private var tint: Color {
        switch entry.kind {
        case "charging": .green
        case "discharging": .orange
        case "completed": .blue
        case "failed": .red
        default: .secondary
        }
    }

    private var configurationDescription: String {
        let load: String
        if !entry.highLoad {
            load = AppLanguage.localized("common.disabled")
        } else if entry.gpuLoad {
            load = String.localizedStringWithFormat(
                AppLanguage.localized("history.configuration.cpu_gpu"),
                entry.stressWorkers
            )
        } else {
            load = String.localizedStringWithFormat(
                AppLanguage.localized("history.configuration.cpu"),
                entry.stressWorkers
            )
        }
        let lowerLimit = AppLanguage.localizedPercent(Double(entry.lower))
        let upperLimit = AppLanguage.localizedPercent(Double(entry.upper))
        return String.localizedStringWithFormat(
            AppLanguage.localized("history.configuration.summary"),
            lowerLimit,
            upperLimit,
            load
        )
    }

    private var dateFormat: Date.FormatStyle {
        .dateTime
            .year().month().day()
            .hour().minute().second()
            .locale(AppLanguage.currentLocale)
    }
}
