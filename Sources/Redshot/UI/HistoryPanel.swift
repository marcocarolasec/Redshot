import AppKit
import SwiftUI

/// Panel flotante que no activa la app (así la app anterior sigue en primer plano y ⌘V simulado le llega).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

@MainActor
final class HistoryPanelController {
    static let shared = HistoryPanelController()
    private var panel: KeyablePanel?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if panel == nil { build() }
        guard let panel else { return }
        positionOnMouseScreen(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Redshot"
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        p.minSize = NSSize(width: 640, height: 400)
        p.contentView = NSHostingView(rootView: HistoryView().environmentObject(ClipStore.shared))
        panel = p
    }

    private func positionOnMouseScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        panel.setFrameOrigin(origin)
    }
}
