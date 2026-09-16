import SwiftUI

struct HelperOnboardingView: View {
    @ObservedObject var helper: HelperManager
    let onContinueWithoutHelper: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 58))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("onboarding.helper.title")
                    .font(.largeTitle.bold())
                Text("onboarding.helper.subtitle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 18) {
                onboardingRow(
                    icon: "battery.100percent.bolt",
                    title: "onboarding.helper.control.title",
                    detail: "onboarding.helper.control.detail"
                )
                onboardingRow(
                    icon: "lock.shield",
                    title: "onboarding.helper.authorization.title",
                    detail: "onboarding.helper.authorization.detail"
                )
                onboardingRow(
                    icon: "trash",
                    title: "onboarding.helper.removable.title",
                    detail: "onboarding.helper.removable.detail"
                )
            }
            .padding(20)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))

            if case .unavailable = helper.state, !helper.message.isEmpty {
                Label(helper.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 10) {
                Button(action: helper.install) {
                    if helper.state == .installing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("onboarding.helper.install")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(helper.state == .installing || helper.state == .uninstalling)

                Button("onboarding.helper.later", action: onContinueWithoutHelper)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(helper.state == .installing || helper.state == .uninstalling)
            }

            Text("onboarding.helper.note")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(width: 540)
        .interactiveDismissDisabled(helper.state == .installing || helper.state == .uninstalling)
    }

    private func onboardingRow(
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
