import SwiftUI

struct CycleSettingsTabView: View {
    @ObservedObject var cycle: CycleController
    @ObservedObject var helper: HelperManager
    @Binding var lowerLimit: Double
    @Binding var upperLimit: Double
    @State private var showsUninstallConfirmation = false

    var body: some View {
        automationCard
    }

    private var automationCard: some View {
        GroupBox("cycle.group.title") {
            VStack(spacing: 14) {
                helperStatus
                if helper.requiresUpdate {
                    helperUpdateNotice
                }
                Divider()
                thresholdControls
                Label("cycle.sleep_prevention.note", systemImage: "moon.zzz")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
        }
        .confirmationDialog(
            "helper.uninstall.confirm.title",
            isPresented: $showsUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("helper.action.uninstall", role: .destructive, action: cycle.uninstallHelper)
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("helper.uninstall.confirm.message")
        }
    }

    private var helperStatus: some View {
        HStack {
            Label(helper.state.title, systemImage: helperStateIcon)
                .foregroundStyle(helperStateColor)
            Spacer()
            switch helper.state {
            case .notRegistered, .unavailable:
                Button("helper.action.install") { cycle.installHelper() }
            case .installing, .uninstalling:
                ProgressView().controlSize(.small)
            case .enabled:
                HStack(spacing: 10) {
                    if let versionDescription = helper.versionDescription {
                        Text(versionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !helper.requiresUpdate {
                        Button(helperReinstallTitle) {
                            cycle.installHelper()
                        }
                            .controlSize(.small)
                    }
                    Button("helper.action.uninstall", role: .destructive) {
                        showsUninstallConfirmation = true
                    }
                        .controlSize(.small)
                        .disabled(cycle.canStopCycle)
                }
            }
        }
    }

    private var helperUpdateNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("helper.update.available")
                    .font(.headline)
                if let description = helper.updateDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("helper.update.read_only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(helperUpdateTitle) {
                cycle.installHelper()
            }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(cycle.canStopCycle)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var thresholdControls: some View {
        Group {
            LabeledContent("cycle.threshold.start_charging") {
                HStack {
                    Slider(value: $lowerLimit, in: 10...70, step: 5)
                        .frame(width: 180)
                        .disabled(cycle.canStopCycle || helper.requiresUpdate)
                    Text(verbatim: "\(Int(lowerLimit))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            LabeledContent("cycle.threshold.stop_charging") {
                HStack {
                    Slider(value: $upperLimit, in: max(lowerLimit + 10, 40)...100, step: 5)
                        .frame(width: 180)
                        .disabled(cycle.canStopCycle || helper.requiresUpdate)
                    Text(verbatim: "\(Int(upperLimit))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private var helperStateColor: Color {
        helper.state == .enabled && !helper.requiresUpdate ? .green : .orange
    }

    private var helperStateIcon: String {
        if helper.requiresUpdate { return "arrow.triangle.2.circlepath.circle.fill" }
        return helper.state == .enabled ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var helperUpdateTitle: String {
        AppLanguage.localized("helper.action.update")
    }

    private var helperReinstallTitle: String {
        cycle.isRunning
            ? AppLanguage.localized("helper.action.reinstall_and_stop")
            : AppLanguage.localized("helper.action.reinstall")
    }
}
