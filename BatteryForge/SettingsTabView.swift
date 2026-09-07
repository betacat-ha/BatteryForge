import SwiftUI

struct SettingsTabView: View {
    @ObservedObject var cycle: CycleController
    @ObservedObject var helper: HelperManager
    @ObservedObject var updateManager: AppUpdateManager
    @Binding var lowerLimit: Double
    @Binding var upperLimit: Double
    @Binding var workloadEnabled: Bool
    @Binding var workloadLevelRaw: Int
    @Binding var gpuLoadEnabled: Bool
    @Binding var thermalProtectionEnabled: Bool
    @Binding var thermalThreshold: Double
    @Binding var languageRawValue: String

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "settings.title",
                subtitle: "settings.subtitle"
            )
            CycleSettingsTabView(
                cycle: cycle,
                helper: helper,
                lowerLimit: $lowerLimit,
                upperLimit: $upperLimit
            )
            WorkloadSettingsTabView(
                cycle: cycle,
                workloadEnabled: $workloadEnabled,
                workloadLevelRaw: $workloadLevelRaw,
                gpuLoadEnabled: $gpuLoadEnabled,
                thermalProtectionEnabled: $thermalProtectionEnabled,
                thermalThreshold: $thermalThreshold
            )
            updateCard
            languageCard
        }
    }

    private var updateCard: some View {
        GroupBox("app_update.section") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("app_update.channel.label") {
                    Picker("app_update.channel.label", selection: $updateManager.channel) {
                        ForEach(AppUpdateChannel.allCases) { channel in
                            Text(channel.title).tag(channel)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
                Label(updateManager.channel.detail, systemImage: "shippingbox.and.arrow.backward")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text(updateManager.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if updateManager.state == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("app_update.check") {
                            Task { await updateManager.checkForUpdates() }
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var languageCard: some View {
        GroupBox("settings.language.section") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("settings.language.label") {
                    Picker("settings.language.label", selection: $languageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.titleKey).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Divider()
                Label("settings.language.note", systemImage: "globe")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}
