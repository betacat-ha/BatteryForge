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
    @StateObject private var updateManager = AppUpdateManager()

    var body: some Scene {
        WindowGroup(AppLanguage.localized("app.title")) {
            ContentView(updateManager: updateManager)
        }
        .defaultSize(width: 1080, height: 760)
        .environment(\.locale, selectedLanguage.locale)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("app_update.check") {
                    Task { await updateManager.checkForUpdates() }
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(updateManager.state == .checking)
            }
        }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .system
    }
}
