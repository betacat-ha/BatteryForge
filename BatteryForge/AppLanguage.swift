import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    nonisolated static let storageKey = "app.language"

    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    nonisolated var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "settings.language.system"
        case .simplifiedChinese: "settings.language.simplified_chinese"
        case .english: "settings.language.english"
        }
    }

    nonisolated static var currentLocale: Locale {
        current.locale
    }

    nonisolated static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: currentBundle, locale: currentLocale)
    }

    nonisolated private static var current: AppLanguage {
        let storedValue = UserDefaults.standard.string(forKey: storageKey) ?? system.rawValue
        return AppLanguage(rawValue: storedValue) ?? .system
    }

    nonisolated private static var currentBundle: Bundle {
        guard current != .system,
              let path = Bundle.main.path(forResource: current.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}
