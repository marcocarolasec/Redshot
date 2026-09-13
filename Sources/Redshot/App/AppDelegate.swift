import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sin icono en el Dock aunque se ejecute fuera de un bundle (swift run / Xcode).
        NSApp.setActivationPolicy(.accessory)
        Prefs.registerDefaults()
        ScreenshotService.permissionAtLaunch = ScreenshotService.hasScreenRecordingPermission()

        Task { @MainActor in
            Installer.offerMoveToApplicationsIfNeeded()
            ClipboardMonitor.shared.start()
            self.registerHotkeys()
            if Prefs.showWelcomeAtLaunchValue {
                // Retoma el asistente donde tenga sentido según los permisos ya concedidos.
                let step: OnboardingStep
                if !ScreenshotService.hasScreenRecordingPermission() {
                    step = .welcome
                } else if !PasteService.accessibilityGranted {
                    step = .accessibility
                } else {
                    step = .tryIt
                }
                WelcomeWindowController.shared.show(step: step)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    private func registerHotkeys() {
        let hk = HotkeyManager.shared
        NSLog("Redshot: arrancado desde \(Bundle.main.bundlePath), pid \(ProcessInfo.processInfo.processIdentifier)")

        var ok = hk.register(.init(keyCode: Key.v, modifiers: Key.ctrlCmd)) {
            NSLog("Redshot: hotkey ⌃⌘V")
            Task { @MainActor in HistoryPanelController.shared.toggle() }
        }
        NSLog("Redshot: registro ⌃⌘V \(ok ? "OK" : "FALLÓ (¿otra instancia abierta?)")")
        ok = hk.register(.init(keyCode: Key.s, modifiers: Key.ctrlCmd)) {
            NSLog("Redshot: hotkey ⌃⌘S")
            Task { @MainActor in ScreenshotService.shared.capture(.region) }
        }
        NSLog("Redshot: registro ⌃⌘S \(ok ? "OK" : "FALLÓ")")
        ok = hk.register(.init(keyCode: Key.w, modifiers: Key.ctrlCmd)) {
            Task { @MainActor in ScreenshotService.shared.capture(.window) }
        }
        NSLog("Redshot: registro ⌃⌘W \(ok ? "OK" : "FALLÓ")")
        ok = hk.register(.init(keyCode: Key.f, modifiers: Key.ctrlCmd)) {
            Task { @MainActor in ScreenshotService.shared.capture(.screen) }
        }
        NSLog("Redshot: registro ⌃⌘F \(ok ? "OK" : "FALLÓ")")

        // ⌃⌘1…9 pega el 1º…9º más reciente; ⌃⌘0 el 10º.
        for digit in 0...9 {
            let index = digit == 0 ? 9 : digit - 1
            hk.register(.init(keyCode: Key.digits[digit], modifiers: Key.ctrlCmd)) {
                Task { @MainActor in
                    let recent = ClipStore.shared.recent(10)
                    guard index < recent.count else { return }
                    PasteService.copyAndPaste(recent[index])
                }
            }
        }
    }
}
