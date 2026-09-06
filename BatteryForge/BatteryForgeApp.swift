//
//  BatteryForgeApp.swift
//  BatteryForge
//
//  Created by BetaCat on 5/9/26.
//

import SwiftUI

@main
struct BatteryForgeApp: App {
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    var body: some Scene {
        WindowGroup(AppLanguage.localized("app.title")) {
            ContentView()
        }
        .defaultSize(width: 1080, height: 760)
        .environment(\.locale, selectedLanguage.locale)
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .system
    }
}
