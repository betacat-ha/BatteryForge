import SwiftUI

struct HistoryTabView: View {
    let updatedAt: Date

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                title: "运行记录",
                subtitle: "查看已经完成的充放电循环",
                updatedAt: updatedAt
            )
            ContentUnavailableView(
                "暂无运行记录",
                systemImage: "clock.arrow.circlepath",
                description: Text("完成一次充放电循环后，记录将显示在这里。")
            )
            .frame(minHeight: 360)
        }
    }
}
