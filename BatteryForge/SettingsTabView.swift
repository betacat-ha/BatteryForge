import SwiftUI

struct SettingsTabView: View {
    @ObservedObject var cycle: CycleController
    @ObservedObject var helper: HelperManager
    @Binding var lowerLimit: Double
    @Binding var upperLimit: Double
    @Binding var workloadEnabled: Bool
    @Binding var workloadLevelRaw: Int
    @Binding var gpuLoadEnabled: Bool
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
                gpuLoadEnabled: $gpuLoadEnabled
            )
            languageCard
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
