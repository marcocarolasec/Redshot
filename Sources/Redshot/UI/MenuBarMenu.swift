import SwiftUI

@MainActor
struct MenuBarMenu: View {
    @EnvironmentObject var store: ClipStore
    @AppStorage(Prefs.clipboardPaused) private var paused = false
    @ObservedObject private var l10n = Localizer.shared

    // Los atajos globales los gestiona HotkeyManager (Carbon); aquí solo se muestran.
    var body: some View {
        Button(L("History") + "\t⌃⌘V") { HistoryPanelController.shared.toggle() }
        Button(L("How to use…")) { WelcomeWindowController.shared.show() }

        Divider()

        Group {
            Button(L("Capture area") + "\t⌃⌘S") { ScreenshotService.shared.capture(.region) }
            Button(L("Capture window") + "\t⌃⌘W") { ScreenshotService.shared.capture(.window) }
            Button(L("Capture full screen") + "\t⌃⌘F") { ScreenshotService.shared.capture(.screen) }
        }

        Divider()

        let recent = store.recent(8)
        if !recent.isEmpty {
            Menu(L("Recent")) {
                ForEach(recent) { item in
                    Button {
                        PasteService.copy(item)
                    } label: {
                        Label(item.menuTitle, systemImage: item.kind.symbol)
                    }
                }
            }
            Divider()
        }

        Toggle(L("Pause clipboard"), isOn: $paused)

        Button(L("Settings…")) { SettingsOpener.open() }

        Divider()

        Button(L("Quit Redshot")) { NSApplication.shared.terminate(nil) }
    }
}
