import AppKit
import Foundation

enum CaptureMode {
    case region, window, screen
}

/// Captura de pantalla usando /usr/sbin/screencapture (la misma herramienta que usa ⌘⇧4).
/// Requiere el permiso "Grabación de pantalla" para la app en Ajustes del Sistema.
@MainActor
final class ScreenshotService {
    static let shared = ScreenshotService()
    private var running = false

    private init() {}

    /// Estado del permiso al arrancar el proceso. Si cambia a concedido durante la ejecución, hay que reiniciar.
    static var permissionAtLaunch = false

    nonisolated static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Dispara el diálogo del sistema y abre el panel de Grabación de pantalla.
    nonisolated static func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func capture(_ mode: CaptureMode) {
        guard !running else { return }
        running = true

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("redshot-\(UUID().uuidString).png")

        var args = ["-x", "-t", "png"]        // -x: sin sonido
        switch mode {
        case .region: args.append("-i")       // selección interactiva (Espacio cambia a ventana)
        case .window: args += ["-i", "-W"]    // interactivo empezando en modo ventana
        case .screen: args.append("-m")       // solo pantalla principal, sin interacción
        }
        args.append(tmp.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        process.terminationHandler = { p in
            NSLog("Redshot: screencapture terminó con código \(p.terminationStatus)")
            DispatchQueue.main.async {
                Task { @MainActor in
                    ScreenshotService.shared.finish(tmp)
                }
            }
        }
        do {
            NSLog("Redshot: lanzando screencapture \(args.joined(separator: " "))")
            try process.run()
        } catch {
            NSLog("Redshot: error lanzando screencapture: \(error)")
            running = false
            ClipStore.shared.reportError("No se pudo lanzar screencapture: \(error)")
        }
    }

    private func finish(_ file: URL) {
        running = false
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = try? Data(contentsOf: file), !data.isEmpty else {
            NSLog("Redshot: sin fichero de captura (cancelado con Esc o sin permiso de Grabación de pantalla)")
            if !Self.hasScreenRecordingPermission() || !Self.permissionAtLaunch {
                WelcomeWindowController.shared.show(step: .screenRecording)
            }
            return
        }
        NSLog("Redshot: captura de \(data.count) bytes")

        let store = ClipStore.shared
        guard let item = store.addImage(pngData: data, kind: .screenshot, source: SourceApp.frontmost) else { return }

        if Prefs.copyScreenshotToClipboardValue {
            PasteService.copy(item)
        }

        let folder = Prefs.screenshotFolderValue
        if !folder.isEmpty {
            let dest = URL(fileURLWithPath: folder, isDirectory: true)
                .appendingPathComponent(item.imagePath ?? "captura.png")
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: dest, options: .atomic)
        }

        OCRService.runIfEnabled(for: item)
        if Prefs.captureSoundValue {
            NSSound(named: "Pop")?.play()
        }
        if Prefs.openEditorAfterCaptureValue {
            EditorWindowController.shared.open(item)
        }
    }
}
