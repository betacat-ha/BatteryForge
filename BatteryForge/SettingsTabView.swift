import SwiftUI

struct SettingsTabView: View {
    @Binding var languageRawValue: String

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "settings.title",
                subtitle: "settings.subtitle"
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
