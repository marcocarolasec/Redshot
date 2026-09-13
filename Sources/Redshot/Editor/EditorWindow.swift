import AppKit
import SwiftUI

/// Abre el editor de anotaciones sobre una imagen del historial.
@MainActor
final class EditorWindowController {
    static let shared = EditorWindowController()
    private var window: NSWindow?

    private init() {}

    func open(_ item: ClipItem) {
        guard item.kind.isImage,
              let image = ClipStore.shared.image(for: item),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        window?.close()
        let model = EditorModel(base: cg, sourceItem: item)

        // Tamaño: imagen a escala 1:1 (en puntos) si cabe, si no ajustada al 85% de la pantalla.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let pts = CGSize(width: CGFloat(cg.width) / backing, height: CGFloat(cg.height) / backing)
        let maxW = screen.width * 0.85, maxH = screen.height * 0.85 - 60
        let fit = min(1, maxW / pts.width, maxH / pts.height)
        let w = max(960, pts.width * fit + 32)
        let h = max(500, pts.height * fit + 32 + 110)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = L("Edit screenshot")
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 960, height: 440)
        win.contentView = NSHostingView(rootView: EditorView(model: model, onClose: { [weak self] in self?.window?.close() }))
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

@MainActor
struct EditorView: View {
    @ObservedObject var model: EditorModel
    let onClose: () -> Void
    @State private var confirmDiscard = false
    @ObservedObject private var l10n = Localizer.shared

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            AnnotationCanvas(model: model)
            Divider()
            statusBar
        }
        .alert(L("Discard changes?"), isPresented: $confirmDiscard) {
            Button(L("Discard"), role: .destructive) { onClose() }
            Button(L("Keep editing"), role: .cancel) {}
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(EditorTool.allCases) { t in
                        ToolButton(tool: t, selected: model.tool == t) { model.tool = t }
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

                ColorPicker("", selection: $model.color, supportsOpacity: false)
                    .labelsHidden()
                    .help(L("Color"))

                Picker("Width", selection: $model.lineWidth) {
                    Text(L("Thin")).tag(CGFloat(2))
                    Text(L("Normal")).tag(CGFloat(4))
                    Text(L("Thick")).tag(CGFloat(7))
                    Text(L("Very thick")).tag(CGFloat(12))
                }
                .labelsHidden()
                .frame(width: 110)
                .help(L("Stroke width"))

                Picker("Text", selection: $model.fontSize) {
                    Text(L("Text S")).tag(CGFloat(20))
                    Text(L("Text M")).tag(CGFloat(28))
                    Text(L("Text L")).tag(CGFloat(40))
                    Text(L("Text XL")).tag(CGFloat(56))
                }
                .labelsHidden()
                .frame(width: 100)
                .help(L("Text size"))

                Spacer()

                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo).help(L("Undo (⌘Z)"))
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo).help(L("Redo (⇧⌘Z)"))
            }

            HStack(spacing: 10) {
                Text(model.tool.label).font(.callout).bold()
                Text(model.tool.hint).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if model.crop != nil {
                    Button(L("Remove crop")) { model.clearCrop() }.controlSize(.small)
                }
                Spacer()
                Button(L("Cancel")) {
                    if model.isDirty { confirmDiscard = true } else { onClose() }
                }
                Button(L("Export…")) { model.exportPNG() }
                Button(L("Copy")) {
                    model.copyToClipboard()
                    onClose()
                }
                .help(L("Copies the result to the clipboard and closes, without saving it to the history"))
                Button(L("Save")) {
                    model.saveAsNewItem()
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .help(L("Saves as a new history item, copies it to the clipboard and closes"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var statusBar: some View {
        HStack {
            Text(L("⇧ forces square, circle or 45°  ·  Delete removes the selection  ·  ⌘Z undoes"))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(model.base.width) × \(model.base.height) px" + (model.crop.map { " → \(Int($0.width)) × \(Int($0.height))" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}

/// Botón de herramienta con icono y nombre; sustituye al Picker segmentado, que no renderiza imágenes fiablemente.
private struct ToolButton: View {
    let tool: EditorTool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 18)
                Text(tool.label)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
            .frame(width: 58, height: 36)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tool.hint)
    }
}
