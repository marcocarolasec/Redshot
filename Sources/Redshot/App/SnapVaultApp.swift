import SwiftUI

@main
@MainActor
struct RedshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ClipStore.shared

    var body: some Scene {
        MenuBarExtra("Redshot", systemImage: "camera.viewfinder") {
            MenuBarMenu().environmentObject(store)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
