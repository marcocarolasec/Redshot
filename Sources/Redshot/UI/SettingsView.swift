import AppKit
import ServiceManagement
import SwiftUI

/// Ventana de ajustes propia. El selector showSettingsWindow: no responde de forma fiable
/// en apps de barra de menús en Sonoma, así que se gestiona a mano.
@MainActor
enum SettingsOpener {
    private static var window: NSWindow?

    static func open() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        window?.title = L("Redshot Settings")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject private var l10n = Localizer.shared

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            ClipboardSettingsTab()
                .tabItem { Label(L("Clipboard"), systemImage: "doc.on.clipboard") }
            CaptureSettingsTab()
                .tabItem { Label(L("Screenshots"), systemImage: "camera") }
            ShortcutsSettingsTab()
                .tabItem { Label(L("Shortcuts"), systemImage: "keyboard") }
        }
        .frame(width: 500, height: 500)
        .id(l10n.effective) // fuerza re-render completo al cambiar de idioma
    }
}

// MARK: - General

@MainActor
private struct GeneralSettingsTab: View {
    @ObservedObject private var l10n = Localizer.shared
    @AppStorage(Prefs.launchAtLogin) private var launchAtLogin = false
    @AppStorage(Prefs.showWelcomeAtLaunch) private var showWelcome = true
    @AppStorage(Prefs.maxItems) private var maxItems = 1000
    @State private var language: AppLanguage = Localizer.shared.setting
    @State private var screenGranted = ScreenshotService.hasScreenRecordingPermission()
    @State private var axGranted = PasteService.accessibilityGranted
    @State private var loginError: String?
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Picker(L("Language"), selection: $language) {
                    Text(L("System")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.en)
                    Text("Español").tag(AppLanguage.es)
                }
                .onChange(of: language) { _, new in Localizer.shared.setting = new }
                Toggle(L("Open Redshot at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle(L("Show the welcome guide at launch"), isOn: $showWelcome)
            }

            Section {
                PermissionRow(
                    title: L("Screen Recording"),
                    detail: L("Required to take screenshots."),
                    granted: screenGranted,
                    action: { ScreenshotService.openScreenRecordingSettings() }
                )
                PermissionRow(
                    title: L("Accessibility"),
                    detail: L("To paste directly when you pick an item."),
                    granted: axGranted,
                    action: { PasteService.requestAccessibility() }
                )
            } header: {
                Text(L("Permissions"))
            } footer: {
                Text(L("If you just granted Screen Recording, restart Redshot to apply it."))
            }

            Section {
                LabeledContent(L("History size")) {
                    Picker("", selection: $maxItems) {
                        Text(L("500 items")).tag(500)
                        Text(L("1,000 items")).tag(1000)
                        Text(L("2,500 items")).tag(2500)
                        Text(L("5,000 items")).tag(5000)
                        Text(L("10,000 items")).tag(10000)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                Button(L("Open the welcome guide…")) { WelcomeWindowController.shared.show() }
            } footer: {
                Text(L("Above the limit the oldest items are removed. Pinned items are never removed."))
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            screenGranted = ScreenshotService.hasScreenRecordingPermission()
            axGranted = PasteService.accessibilityGranted
        }
    }
}

@MainActor
private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text(L("Granted")).font(.caption).foregroundStyle(.secondary)
            } else {
                Button(L("Grant…"), action: action).controlSize(.small)
            }
        }
    }
}

// MARK: - Portapapeles

@MainActor
private struct ClipboardSettingsTab: View {
    @ObservedObject private var l10n = Localizer.shared
    @AppStorage(Prefs.pasteOnSelect) private var pasteOnSelect = true
    @AppStorage(Prefs.skipSensitive) private var skipSensitive = true
    @AppStorage(Prefs.clipboardPaused) private var paused = false
    @AppStorage(Prefs.ignoredApps) private var ignoredApps = ""

    /// El campo se edita una app por línea; se guarda separado por comas.
    private var ignoredAppsLines: Binding<String> {
        Binding(
            get: { ignoredApps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n") },
            set: { ignoredApps = $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ") }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle(L("Save what I copy"), isOn: Binding(get: { !paused }, set: { paused = !$0 }))
                Toggle(L("Paste directly when I pick an item"), isOn: $pasteOnSelect)
                Toggle(L("Don't save content that looks sensitive"), isOn: $skipSensitive)
            } footer: {
                Text(L("Sensitive: API tokens, private keys, JWTs and valid card numbers. Anything 1Password or Bitwarden mark as concealed is never saved."))
            }

            Section {
                TextEditor(text: ignoredAppsLines)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
            } header: {
                Text(L("Ignored apps"))
            } footer: {
                Text(L("One app identifier per line (for example com.apple.Terminal). Nothing copied from these apps is saved."))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Capturas

@MainActor
private struct CaptureSettingsTab: View {
    @ObservedObject private var l10n = Localizer.shared
    @AppStorage(Prefs.copyScreenshotToClipboard) private var copyToClipboard = true
    @AppStorage(Prefs.captureSound) private var sound = true
    @AppStorage(Prefs.openEditorAfterCapture) private var openEditor = true
    @AppStorage(Prefs.ocrEnabled) private var ocr = true
    @AppStorage(Prefs.screenshotFolder) private var folder = ""

    var body: some View {
        Form {
            Section {
                Toggle(L("Open the editor after capturing"), isOn: $openEditor)
                Toggle(L("Copy the screenshot to the clipboard"), isOn: $copyToClipboard)
                Toggle(L("Capture sound"), isOn: $sound)
                Toggle(L("Recognize text in screenshots (OCR)"), isOn: $ocr)
            } footer: {
                Text(L("The editor offers arrows, shapes, text, pixelation and cropping; saving creates a new item and keeps the original. With OCR you can search the text inside images."))
            }

            Section {
                LabeledContent(L("Also save to")) {
                    HStack {
                        Text(folder.isEmpty ? L("No folder") : (folder as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(folder.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(L("Choose…")) { pickFolder() }.controlSize(.small)
                        if !folder.isEmpty {
                            Button(L("Remove")) { folder = "" }.controlSize(.small)
                        }
                    }
                }
            } footer: {
                Text(L("Screenshots always stay in the history. This adds a PNG copy in the folder you choose."))
            }
        }
        .formStyle(.grouped)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Choose")
        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
        }
    }
}

// MARK: - Atajos

@MainActor
private struct ShortcutsSettingsTab: View {
    @ObservedObject private var l10n = Localizer.shared

    var body: some View {
        Form {
            Section {
                ShortcutRow(keys: "⌃⌘V", text: L("Open or close the history"))
                ShortcutRow(keys: "⌃⌘S", text: L("Capture area"))
                ShortcutRow(keys: "⌃⌘W", text: L("Capture window"))
                ShortcutRow(keys: "⌃⌘F", text: L("Capture full screen"))
                ShortcutRow(keys: "⌃⌘1…9", text: L("Paste the 1st…9th most recent item"))
                ShortcutRow(keys: "⌃⌘0", text: L("Paste the 10th"))
            } footer: {
                Text(L("While capturing an area: Space switches to window mode, Esc cancels. In the history: Enter pastes the first result, Esc closes."))
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRow: View {
    let keys: String
    let text: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(.body, design: .monospaced)).bold()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                .frame(width: 90, alignment: .leading)
            Text(text)
        }
    }
}
