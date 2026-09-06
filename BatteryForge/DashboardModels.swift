import Foundation

enum SidebarPage: String, Hashable {
    case overview
    case cycle
    case workload
    case history
}

enum WorkloadLevel: Int, CaseIterable, Identifiable {
    case gentle
    case balanced
    case maximum

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .gentle: String(localized: "workload.level.gentle")
        case .balanced: String(localized: "workload.level.balanced")
        case .maximum: String(localized: "workload.level.maximum")
        }
    }

    var detail: String {
        switch self {
        case .gentle: String(localized: "workload.level.gentle.detail")
        case .balanced: String(localized: "workload.level.balanced.detail")
        case .maximum: String(localized: "workload.level.maximum.detail")
        }
    }

    func workerCount(processorCount: Int) -> Int {
        switch self {
        case .gentle: max(processorCount / 4, 1)
        case .balanced: max(processorCount / 2, 1)
        case .maximum: max(processorCount - 1, 1)
        }
    }
}
