import AppKit
import SwiftUI

struct AboutTabView: View {
    @ObservedObject var updateManager: AppUpdateManager
    private let projectURL = URL(string: "https://github.com/betacat-ha/BatteryForge")!
    private let licenseURL = URL(string: "https://github.com/betacat-ha/BatteryForge/blob/main/LICENSE")!
    private let noticesURL = URL(string: "https://github.com/betacat-ha/BatteryForge/blob/main/THIRD_PARTY_NOTICES.md")!

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "about.title",
                subtitle: "about.subtitle"
            )

            GroupBox {
                HStack(spacing: 22) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("app.title")
                            .font(.title.bold())
                        Text(versionDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("about.description")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("about.resources") {
                VStack(spacing: 0) {
                    resourceLink(
                        title: "about.project_homepage",
                        icon: "chevron.left.forwardslash.chevron.right",
                        destination: projectURL
                    )
                    Divider()
                    resourceLink(
                        title: "about.license",
                        icon: "doc.text",
                        destination: licenseURL
                    )
                    Divider()
                    resourceLink(
                        title: "about.third_party_notices",
                        icon: "shippingbox",
                        destination: noticesURL
                    )
                }
                .padding(.horizontal, 8)
            }

            GroupBox("app_update.section") {
                HStack(spacing: 12) {
                    Image(systemName: updateIcon)
                        .foregroundStyle(updateColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("app_update.title")
                            .font(.headline)
                        Text(updateManager.statusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if updateManager.state == .checking {
                        ProgressView().controlSize(.small)
                    } else if case .updateAvailable = updateManager.state {
                        Button("app_update.download") { updateManager.openUpdate() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("app_update.check") {
                            Task { await updateManager.checkForUpdates() }
                        }
                    }
                }
                .padding(8)
            }

            Text("about.copyright")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return String.localizedStringWithFormat(
            AppLanguage.localized("about.version_format"),
            version,
            build
        )
    }

    private var updateIcon: String {
        switch updateManager.state {
        case .updateAvailable: "arrow.down.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .upToDate: "checkmark.circle.fill"
        default: "arrow.triangle.2.circlepath"
        }
    }

    private var updateColor: Color {
        switch updateManager.state {
        case .updateAvailable: .accentColor
        case .failed: .orange
        case .upToDate: .green
        default: .secondary
        }
    }

    private func resourceLink(
        title: LocalizedStringKey,
        icon: String,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(.tint)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

struct AboutTabView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            AboutTabView(updateManager: AppUpdateManager())
                .padding(28)
                .frame(maxWidth: 980)
        }
        .frame(width: 900, height: 680)
    }
}
