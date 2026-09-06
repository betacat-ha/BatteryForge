import Foundation

enum SidebarPage: String, Hashable {
    case overview
    case history
    case settings
}

enum WorkloadLevel: Int, CaseIterable, Identifiable {
    case gentle
    case balanced
    case maximum

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .gentle: String(localized: "workload.level.gentle", locale: AppLanguage.currentLocale)
        case .balanced: String(localized: "workload.level.balanced", locale: AppLanguage.currentLocale)
        case .maximum: String(localized: "workload.level.maximum", locale: AppLanguage.currentLocale)
        }
    }

    var detail: String {
        switch self {
        case .gentle: String(localized: "workload.level.gentle.detail", locale: AppLanguage.currentLocale)
        case .balanced: String(localized: "workload.level.balanced.detail", locale: AppLanguage.currentLocale)
        case .maximum: String(localized: "workload.level.maximum.detail", locale: AppLanguage.currentLocale)
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
