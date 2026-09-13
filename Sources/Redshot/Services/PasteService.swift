import AppKit
import ApplicationServices
import Foundation

/// Copia un item al portapapeles y, opcionalmente, simula ⌘V en la app activa.
@MainActor
enum PasteService {
    static func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let store = ClipStore.shared

        switch item.kind {
        case .image, .screenshot:
            var objects: [NSPasteboardWriting] = []
            if let url = store.images.url(for: item.imagePath) {
                if let image = NSImage(contentsOf: url) { objects.append(image) }
                objects.append(url as NSURL)
            }
            pb.writeObjects(objects)
        case .file:
            if let path = item.text {
                pb.writeObjects([URL(fileURLWithPath: path) as NSURL])
            }
        default:
            pb.setString(item.text ?? "", forType: .string)
        }
        ClipboardMonitor.shared.markOwnWrite()
    }

    /// Copia y pega en la app que estaba activa. Requiere permiso de Accesibilidad para el ⌘V simulado.
    static func copyAndPaste(_ item: ClipItem) {
        copy(item)
        guard Prefs.pasteOnSelectValue else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            simulatePaste()
        }
    }

    nonisolated static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    nonisolated static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func simulatePaste() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
