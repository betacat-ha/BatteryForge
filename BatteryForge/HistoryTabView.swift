import SwiftUI

struct HistoryTabView: View {
    let updatedAt: Date

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "history.title",
                subtitle: "history.subtitle",
                updatedAt: updatedAt
            )
            ContentUnavailableView(
                "history.empty.title",
                systemImage: "clock.arrow.circlepath",
                description: Text("history.empty.description")
            )
            .frame(minHeight: 360)
        }
    }
}
