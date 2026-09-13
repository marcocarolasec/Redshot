import Foundation

/// Claves de UserDefaults. Las vistas usan @AppStorage con estas mismas claves;
/// los servicios leen a través de los accesores estáticos.
enum Prefs {
    static let launchAtLogin = "launchAtLogin"
    static let maxItems = "maxItems"
    static let ocrEnabled = "ocrEnabled"
    static let copyScreenshotToClipboard = "copyScreenshotToClipboard"
    static let pasteOnSelect = "pasteOnSelect"
    static let skipSensitive = "skipSensitive"
    static let ignoredApps = "ignoredApps"
    static let clipboardPaused = "clipboardPaused"
    static let screenshotFolder = "screenshotFolder"
    static let showWelcomeAtLaunch = "showWelcomeAtLaunch"
    static let captureSound = "captureSound"
    static let openEditorAfterCapture = "openEditorAfterCapture"

    static let defaults: [String: Any] = [
        maxItems: 1000,
        ocrEnabled: true,
        copyScreenshotToClipboard: true,
        pasteOnSelect: true,
        skipSensitive: true,
        ignoredApps: "com.1password.1password, com.agilebits.onepassword7, com.bitwarden.desktop, org.keepassxc.keepassxc, com.apple.keychainaccess",
        clipboardPaused: false,
        screenshotFolder: "",
        showWelcomeAtLaunch: true,
        captureSound: true,
        openEditorAfterCapture: true,
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaults)
    }

    private static var d: UserDefaults { .standard }

    static var maxItemsValue: Int { max(50, d.integer(forKey: maxItems)) }
    static var ocrEnabledValue: Bool { d.bool(forKey: ocrEnabled) }
    static var copyScreenshotToClipboardValue: Bool { d.bool(forKey: copyScreenshotToClipboard) }
    static var pasteOnSelectValue: Bool { d.bool(forKey: pasteOnSelect) }
    static var skipSensitiveValue: Bool { d.bool(forKey: skipSensitive) }
    static var clipboardPausedValue: Bool { d.bool(forKey: clipboardPaused) }
    static var screenshotFolderValue: String { d.string(forKey: screenshotFolder) ?? "" }
    static var showWelcomeAtLaunchValue: Bool { d.bool(forKey: showWelcomeAtLaunch) }
    static var captureSoundValue: Bool { d.bool(forKey: captureSound) }
    static var openEditorAfterCaptureValue: Bool { d.bool(forKey: openEditorAfterCapture) }

    static var ignoredBundleIDs: Set<String> {
        let raw = d.string(forKey: ignoredApps) ?? ""
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}
