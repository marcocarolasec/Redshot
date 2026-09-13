import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    let base: CGImage
    let sourceItem: ClipItem

    @Published var annotations: [Annotation] = []
    @Published var selectedID: UUID?
    @Published var tool: EditorTool = .arrow
    @Published var color: Color = .red
    @Published var lineWidth: CGFloat = 4
    @Published var fontSize: CGFloat = 28
    @Published var crop: CGRect?
    @Published private(set) var undoStack: [Snapshot] = []
    @Published private(set) var redoStack: [Snapshot] = []

    struct Snapshot {
        var annotations: [Annotation]
        var crop: CGRect?
    }

    var nsColor: NSColor { NSColor(color) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isDirty: Bool { !annotations.isEmpty || crop != nil }
    var pixelSize: CGSize { CGSize(width: base.width, height: base.height) }

    /// Trazo y fuente se escalan con la resolución (retina = 2x) para que se vean igual en pantalla.
    let resolutionScale: CGFloat

    init(base: CGImage, sourceItem: ClipItem) {
        self.base = base
        self.sourceItem = sourceItem
        self.resolutionScale = max(1, (CGFloat(base.width) / 1400).rounded())
    }

    // MARK: - Undo

    func pushUndo() {
        undoStack.append(Snapshot(annotations: annotations, crop: crop))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(Snapshot(annotations: annotations, crop: crop))
        annotations = s.annotations
        crop = s.crop
        selectedID = nil
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(Snapshot(annotations: annotations, crop: crop))
        annotations = s.annotations
        crop = s.crop
        selectedID = nil
    }

    // MARK: - Edición

    func add(_ a: Annotation) {
        pushUndo()
        annotations.append(a)
    }

    func update(_ a: Annotation) {
        if let i = annotations.firstIndex(where: { $0.id == a.id }) {
            annotations[i] = a
        }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        pushUndo()
        annotations.removeAll { $0.id == id }
        selectedID = nil
    }

    func clearCrop() {
        guard crop != nil else { return }
        pushUndo()
        crop = nil
    }

    func makeAnnotation(kind: Annotation.Kind, at p: CGPoint) -> Annotation {
        Annotation(kind: kind, start: p, end: p, color: nsColor,
                   lineWidth: lineWidth * resolutionScale, fontSize: fontSize * resolutionScale)
    }

    // MARK: - Salida

    func renderFinal() -> CGImage? {
        AnnotationRenderer.render(base: base, annotations: annotations, crop: crop)
    }

    func copyToClipboard() {
        guard let img = renderFinal(), let png = AnnotationRenderer.pngData(img) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        ClipboardMonitor.shared.markOwnWrite()
    }

    /// Guarda como nuevo elemento del historial. El original se conserva.
    @discardableResult
    func saveAsNewItem() -> ClipItem? {
        guard let img = renderFinal(), let png = AnnotationRenderer.pngData(img) else { return nil }
        let source = SourceApp(name: sourceItem.sourceAppName, bundleID: sourceItem.sourceBundleID)
        guard let item = ClipStore.shared.addImage(pngData: png, kind: .screenshot, source: source) else { return nil }
        if let cat = sourceItem.category { ClipStore.shared.setCategory(item, cat) }
        if Prefs.copyScreenshotToClipboardValue {
            PasteService.copy(item)
        }
        OCRService.runIfEnabled(for: item)
        return item
    }

    func exportPNG() {
        guard let img = renderFinal(), let png = AnnotationRenderer.pngData(img) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot-\(Int(Date().timeIntervalSince1970)).png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }
}
