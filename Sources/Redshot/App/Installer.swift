import AppKit
import Foundation

/// Si la app se abre desde un DMG o desde Descargas, ofrece copiarla a Aplicaciones y relanzarla.
@MainActor
enum Installer {
    private static let destination = "/Applications/Redshot.app"

    static var isRunningFromApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    /// Solo aplica a un bundle .app real (no a `swift run` ni a Xcode).
    private static var isRealBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static func offerMoveToApplicationsIfNeeded() {
        guard isRealBundle, !isRunningFromApplications else { return }
        guard !UserDefaults.standard.bool(forKey: "installerDeclined") else { return }

        let alert = NSAlert()
        alert.messageText = L("Move Redshot to Applications?")
        alert.informativeText = LF("It's running from %@. To work reliably and keep its permissions, it should be in the Applications folder.", locationDescription)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("Move to Applications"))
        alert.addButton(withTitle: L("Not now"))
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: "installerDeclined")
            return
        }

        do {
            try install()
        } catch {
            let err = NSAlert()
            err.messageText = L("Couldn't move the app")
            err.informativeText = error.localizedDescription
            err.runModal()
        }
    }

    private static var locationDescription: String {
        let path = Bundle.main.bundlePath
        if path.hasPrefix("/Volumes/") { return L("a disk image") }
        if path.contains("/Downloads/") { return L("the Downloads folder") }
        return (path as NSString).deletingLastPathComponent
    }

    private static func install() throws {
        let fm = FileManager.default
        let source = Bundle.main.bundlePath
        if fm.fileExists(atPath: destination) {
            try fm.removeItem(atPath: destination)
        }
        try fm.copyItem(atPath: source, toPath: destination)

        // Quita la cuarentena de la copia para que no vuelva a salir el aviso de Gatekeeper.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", destination]
        try? xattr.run()
        xattr.waitUntilExit()

        // Relanza desde Aplicaciones y cierra esta instancia.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.8; /usr/bin/open \"\(destination)\""]
        try relaunch.run()
        NSApp.terminate(nil)
    }
}
