import AppKit
import Combine
import SwiftUI

/// Lienzo AppKit: dibuja la imagen ajustada a la vista y gestiona ratón y teclado.
/// Todas las anotaciones se guardan en píxeles de la imagen; aquí solo se convierte a/desde la vista.
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    let model: EditorModel
    private var cancellable: AnyCancellable?

    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var dragOriginal: Annotation?
    private var cropStart: CGPoint?
    private var textField: NSTextField?
    private var editingTextID: UUID?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        cancellable = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.needsDisplay = true }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Geometría

    private var imageRect: CGRect {
        let size = model.pixelSize
        let inset = bounds.insetBy(dx: 16, dy: 16)
        guard size.width > 0, size.height > 0, inset.width > 0, inset.height > 0 else { return .zero }
        let scale = min(inset.width / size.width, inset.height / size.height, 1.0)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: inset.midX - w / 2, y: inset.midY - h / 2, width: w, height: h)
    }

    private var scale: CGFloat {
        let r = imageRect
        return r.width > 0 ? r.width / model.pixelSize.width : 1
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        let x = ((p.x - r.minX) / scale).rounded()
        let y = ((p.y - r.minY) / scale).rounded()
        return CGPoint(x: min(max(0, x), model.pixelSize.width), y: min(max(0, y), model.pixelSize.height))
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: r.minX + p.x * scale, y: r.minY + p.y * scale)
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    // MARK: - Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = imageRect
        guard r.width > 0 else { return }

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 12, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(r)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: r)
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high

        var annotations = model.annotations
        if let draft { annotations.append(draft) }
        AnnotationRenderer.draw(base: model.base, annotations: annotations, selected: model.selectedID,
                                crop: model.crop, showCropOverlay: true, in: ctx)
        ctx.restoreGState()
    }

    // MARK: - Ratón

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitTextEditing()
        let p = toImage(convert(event.locationInWindow, from: nil))
        dragStart = p

        switch model.tool {
        case .select:
            let hit = model.annotations.last { $0.bounds.insetBy(dx: -6 / scale, dy: -6 / scale).contains(p) }
            model.selectedID = hit?.id
            dragOriginal = hit
            if hit != nil { model.pushUndo() }

        case .crop:
            cropStart = p
            model.pushUndo()
            model.crop = CGRect(origin: p, size: .zero)

        case .text:
            var a = model.makeAnnotation(kind: .text, at: p)
            a.text = ""
            model.add(a)
            beginTextEditing(a)

        case .arrow: draft = model.makeAnnotation(kind: .arrow, at: p)
        case .line: draft = model.makeAnnotation(kind: .line, at: p)
        case .rect: draft = model.makeAnnotation(kind: .rect, at: p)
        case .ellipse: draft = model.makeAnnotation(kind: .ellipse, at: p)
        case .blur: draft = model.makeAnnotation(kind: .blur, at: p)
        case .highlight: draft = model.makeAnnotation(kind: .highlight, at: p)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = toImage(convert(event.locationInWindow, from: nil))
        guard let start = dragStart else { return }
        let shift = event.modifierFlags.contains(.shift)

        if var d = draft {
            d.end = shift ? constrained(from: d.start, to: p) : p
            draft = d
        } else if model.tool == .select, let original = dragOriginal, let id = model.selectedID {
            var moved = original
            moved.move(by: CGPoint(x: p.x - start.x, y: p.y - start.y))
            if moved.id == id { model.update(moved) }
        } else if model.tool == .crop, let c = cropStart {
            model.crop = CGRect(x: min(c.x, p.x), y: min(c.y, p.y), width: abs(p.x - c.x), height: abs(p.y - c.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let d = draft {
            let dist = hypot(d.end.x - d.start.x, d.end.y - d.start.y)
            if dist >= 3 { model.add(d) }
            draft = nil
        }
        if model.tool == .crop, let c = model.crop, c.width < 8 || c.height < 8 {
            model.crop = nil
            model.undo()
        }
        cropStart = nil
        dragStart = nil
        dragOriginal = nil
        needsDisplay = true
    }

    /// Con ⇧: cuadrado/círculo para formas, ángulos de 45° para líneas.
    private func constrained(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        switch model.tool {
        case .rect, .ellipse, .blur, .highlight:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: a.x + side * (dx < 0 ? -1 : 1), y: a.y + side * (dy < 0 ? -1 : 1))
        default:
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            return CGPoint(x: a.x + len * cos(angle), y: a.y + len * sin(angle))
        }
    }

    // MARK: - Teclado

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        switch (event.keyCode, cmd) {
        case (51, false), (117, false):           // backspace / delete
            model.deleteSelected()
        case (53, false):                          // esc
            model.selectedID = nil
            commitTextEditing()
        case (6, true) where shift:                // ⇧⌘Z
            model.redo()
        case (6, true):                            // ⌘Z
            model.undo()
        case (8, true):                            // ⌘C
            model.copyToClipboard()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Texto inline

    private func beginTextEditing(_ a: Annotation) {
        commitTextEditing()
        let origin = toView(a.start)
        let field = NSTextField(frame: NSRect(x: origin.x, y: origin.y, width: 240, height: a.fontSize * scale + 12))
        field.font = NSFont.systemFont(ofSize: max(11, a.fontSize * scale), weight: .semibold)
        field.textColor = a.color
        field.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85)
        field.isBordered = true
        field.focusRingType = .default
        field.placeholderString = "Text"
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        editingTextID = a.id
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if let id = editingTextID { model.annotations.removeAll { $0.id == id } }
            editingTextID = nil
            textField?.removeFromSuperview()
            textField = nil
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    private func commitTextEditing() {
        guard let field = textField, let id = editingTextID else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = model.annotations.firstIndex(where: { $0.id == id }) {
            if text.isEmpty {
                model.annotations.remove(at: i)
            } else {
                model.annotations[i].text = text
            }
        }
        field.removeFromSuperview()
        textField = nil
        editingTextID = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}

struct AnnotationCanvas: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> AnnotationCanvasView {
        AnnotationCanvasView(model: model)
    }

    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) {
        nsView.needsDisplay = true
    }
}
