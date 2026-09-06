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
        case .gentle: "温和"
        case .balanced: "均衡"
        case .maximum: "最大"
        }
    }

    var detail: String {
        switch self {
        case .gentle: "使用约四分之一的 CPU 核心"
        case .balanced: "使用约一半的 CPU 核心"
        case .maximum: "使用除一个核心外的全部 CPU 核心"
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
