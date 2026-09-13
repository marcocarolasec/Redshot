import AppKit
import ServiceManagement
import SwiftUI

/// Asistente de primer arranque: una acción por pantalla, avance automático al conceder permisos.
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    private init() {}

    func show(step: OnboardingStep = .welcome) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Redshot"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(initialStep: step).environmentObject(ClipStore.shared))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .snapVaultOnboardingJump, object: step)
    }

    func close() {
        window?.orderOut(nil)
    }
}

extension Notification.Name {
    static let snapVaultOnboardingJump = Notification.Name("snapVaultOnboardingJump")
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, screenRecording, accessibility, tryIt, done
}

@MainActor
struct OnboardingView: View {
    @EnvironmentObject var store: ClipStore
    @State private var step: OnboardingStep
    @State private var screenGranted = ScreenshotService.hasScreenRecordingPermission()
    @State private var axGranted = PasteService.accessibilityGranted
    @State private var screenshotsAtStart = 0
    @State private var advanceScheduled = false
    @ObservedObject private var l10n = Localizer.shared
    @AppStorage(Prefs.showWelcomeAtLaunch) private var showAtLaunch = true
    @AppStorage(Prefs.launchAtLogin) private var launchAtLogin = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(initialStep: OnboardingStep) {
        _step = State(initialValue: initialStep)
    }

    private var needsRelaunch: Bool { screenGranted && !ScreenshotService.permissionAtLaunch }
    private var screenReady: Bool { screenGranted && !needsRelaunch }
    private var newShots: Int { max(0, screenshotCount - screenshotsAtStart) }
    private var screenshotCount: Int { store.recent(50).filter { $0.kind == .screenshot }.count }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step.rawValue), total: Double(OnboardingStep.allCases.count - 1))
                .progressViewStyle(.linear)
                .padding(.horizontal, 32)
                .padding(.top, 36)

            Spacer(minLength: 0)
            content
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: 480, height: 520)
        .background(.regularMaterial)
        .onReceive(timer) { _ in tick() }
        .onReceive(NotificationCenter.default.publisher(for: .snapVaultOnboardingJump)) { note in
            if let s = note.object as? OnboardingStep { jump(to: s) }
        }
        .onAppear { tick() }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - Lógica

    private func tick() {
        screenGranted = ScreenshotService.hasScreenRecordingPermission()
        axGranted = PasteService.accessibilityGranted

        let done: Bool
        switch step {
        case .screenRecording: done = screenReady
        case .accessibility: done = axGranted
        case .tryIt: done = newShots > 0
        default: done = false
        }
        if done, !advanceScheduled {
            advanceScheduled = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                advanceScheduled = false
                go(1)
            }
        }
    }

    private func go(_ delta: Int) {
        if let next = OnboardingStep(rawValue: step.rawValue + delta) { jump(to: next) }
    }

    private func jump(to next: OnboardingStep) {
        advanceScheduled = false
        if next == .tryIt { screenshotsAtStart = screenshotCount }
        step = next
    }

    // MARK: - Pantallas

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            screen(icon: "camera.viewfinder", title: "Redshot",
                   text: L("Screenshots and clipboard with history.\nEverything stays on your Mac.")) {
                EmptyView()
            }
        case .screenRecording:
            screen(icon: screenReady ? "checkmark.circle.fill" : "rectangle.dashed.badge.record",
                   iconColor: screenReady ? .green : .accentColor,
                   title: L("Permission to capture"),
                   text: screenStatusText) {
                if !screenGranted {
                    bigButton(L("Grant permission"), icon: "gear") { ScreenshotService.openScreenRecordingSettings() }
                    Text(L("System Settings opens. Turn on the Redshot switch and come back here."))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else if needsRelaunch {
                    bigButton(L("Restart Redshot"), icon: "arrow.clockwise") { AppRelauncher.relaunch() }
                    Text(L("macOS applies this permission on restart. It reopens by itself at this point."))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        case .accessibility:
            screen(icon: axGranted ? "checkmark.circle.fill" : "keyboard",
                   iconColor: axGranted ? .green : .accentColor,
                   title: L("Direct paste"),
                   text: axGranted
                        ? L("Done. Picking something from the history pastes it where you were.")
                        : L("Optional: with the Accessibility permission, picking something from the history pastes it directly into the app you were using.")) {
                if !axGranted {
                    bigButton(L("Grant permission"), icon: "hand.raised") { PasteService.requestAccessibility() }
                    Text(L("If you'd rather paste with ⌘V yourself, press Skip."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .tryIt:
            screen(icon: newShots > 0 ? "checkmark.circle.fill" : "camera",
                   iconColor: newShots > 0 ? .green : .accentColor,
                   title: newShots > 0 ? L("Screenshot saved") : L("Take a screenshot"),
                   text: newShots > 0
                        ? L("It's in the history and on the clipboard. The editor opens by itself after each capture to annotate, pixelate or crop.")
                        : L("Press ⌃⌘S or the button. Drag over what you want to capture.")) {
                if newShots == 0 {
                    bigButton(L("Capture now"), icon: "camera") {
                        WelcomeWindowController.shared.close()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            ScreenshotService.shared.capture(.region)
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            WelcomeWindowController.shared.show(step: .tryIt)
                        }
                    }
                    .disabled(!screenReady)
                    if !screenReady {
                        Text(L("The capture permission from the previous step is missing."))
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else if let last = store.recent(20).first(where: { $0.kind == .screenshot }),
                          let img = store.image(for: last) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 6, y: 3)
                }
            }
        case .done:
            screen(icon: "menubar.arrow.up.rectangle", title: L("All set"),
                   text: L("Redshot lives in the menu bar, top right, with this icon:")) {
                Image(systemName: "camera.viewfinder")
                    .font(.title)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
                VStack(alignment: .leading, spacing: 8) {
                    ShortcutRow(keys: "⌃⌘S", text: L("Capture area (goes to the clipboard)"))
                    ShortcutRow(keys: "⌃⌘V", text: L("Open the history"))
                    ShortcutRow(keys: "⌃⌘W", text: L("Capture window"))
                }
                .padding(.top, 4)
                Toggle(L("Open Redshot at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in AppRelauncher.setLaunchAtLogin(on) }
                    .padding(.top, 8)
            }
        }
    }

    private var screenStatusText: String {
        if screenReady { return L("Granted. You can capture now.") }
        if needsRelaunch { return L("Granted. Just restart.") }
        return L("macOS asks every app that takes screenshots for the Screen Recording permission. It's the same one Zoom or CleanShot use.")
    }

    // MARK: - Pie

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button(L("Back")) { go(-1) }
            }
            Spacer()
            switch step {
            case .welcome:
                Button(L("Get started")) { go(1) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            case .screenRecording:
                if screenReady {
                    Button(L("Next")) { go(1) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(L("Skip for now")) { go(1) }
                }
            case .accessibility:
                if axGranted {
                    Button(L("Next")) { go(1) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(L("Skip")) { go(1) }
                }
            case .tryIt:
                Button(newShots > 0 ? L("Next") : L("Skip")) { go(1) }.keyboardShortcut(.defaultAction)
            case .done:
                Toggle(L("Show at launch"), isOn: $showAtLaunch).controlSize(.small)
                Button(L("Open history")) {
                    WelcomeWindowController.shared.close()
                    HistoryPanelController.shared.show()
                }
                Button(L("Close")) { WelcomeWindowController.shared.close() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Piezas

    private func screen<Extra: View>(icon: String, iconColor: Color = .accentColor, title: String, text: String,
                                     @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
                .frame(height: 70)
            Text(title).font(.title).bold()
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            extra()
                .padding(.top, 6)
        }
    }

    private func bigButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(minWidth: 200)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }
}

/// Reinicio de la app (necesario tras conceder Grabación de pantalla) y arranque al iniciar sesión.
enum AppRelauncher {
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.7; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    static func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Redshot: no se pudo cambiar el inicio de sesión: \(error)")
        }
    }
}
