import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ClipCardView: View {
    @EnvironmentObject var store: ClipStore
    let item: ClipItem
    let onSelect: () -> Void

    @State private var hovering = false
    @State private var thumbnail: NSImage?
    @ObservedObject private var l10n = Localizer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 140)
                .clipped()

            HStack(spacing: 6) {
                Image(systemName: item.kind.symbol)
                Text(item.sourceAppName ?? item.kind.label).lineLimit(1)
                if let cat = item.category, !cat.isEmpty {
                    Text(cat)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                }
                Spacer(minLength: 4)
                if item.pinned { Image(systemName: "pin.fill") }
                Text(item.createdAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hovering ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: hovering ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu { menu }
        .onDrag { dragProvider() }
        .task(id: item.thumbPath ?? item.imagePath) { [url = thumbnailURL] in
            guard let url else { return }
            thumbnail = NSImage(contentsOf: url)
        }
    }

    private var thumbnailURL: URL? {
        guard item.kind.isImage else { return nil }
        return store.images.url(for: item.thumbPath ?? item.imagePath)
    }

    // MARK: - Vista previa por tipo

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image, .screenshot:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .color:
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: item.text ?? "") ?? .gray)
                    .frame(width: 56, height: 56)
                Text(item.text ?? "").font(.system(.body, design: .monospaced))
            }
        case .link:
            Text(item.text ?? "")
                .foregroundStyle(.blue)
                .lineLimit(5)
                .font(.callout)
        case .code:
            Text(item.text ?? "")
                .font(.system(.caption, design: .monospaced))
                .lineLimit(9)
        case .file:
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.text ?? ""))
                    .resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading) {
                    Text(URL(fileURLWithPath: item.text ?? "").lastPathComponent).bold()
                    Text(item.text ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        case .text:
            Text(item.text ?? "")
                .lineLimit(8)
                .font(.callout)
        }
    }

    // MARK: - Menú contextual

    @ViewBuilder
    private var menu: some View {
        Group {
            if item.kind.isImage {
                Button(L("Edit…")) { EditorWindowController.shared.open(item) }
            }
            Button(L("Copy")) { PasteService.copy(item) }
            Button(L("Copy and paste")) { onSelect() }
            if item.kind.isImage, let ocr = item.ocrText, !ocr.isEmpty {
                Button(L("Copy text (OCR)")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ocr, forType: .string)
                    ClipboardMonitor.shared.markOwnWrite()
                }
            }
        }
        Divider()
        Group {
            Button(item.pinned ? L("Unpin") : L("Pin")) { store.togglePin(item) }
            Menu(L("Category")) {
                ForEach(["Work", "Personal", "Pentest", "Blog", "Client"], id: \.self) { c in
                    Button(L(c)) { store.setCategory(item, L(c)) }
                }
                Divider()
                Button(L("Remove category")) { store.setCategory(item, nil) }
            }
        }
        Divider()
        Group {
            if item.kind.isImage, let url = store.images.url(for: item.imagePath) {
                Button(L("Open")) { NSWorkspace.shared.open(url) }
                Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            if item.kind == .file, let path = item.text {
                Button(L("Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            if item.kind == .link, let s = item.text, let url = URL(string: s) {
                Button(L("Open link")) { NSWorkspace.shared.open(url) }
            }
        }
        Divider()
        Button(L("Delete"), role: .destructive) { store.delete(item) }
    }

    // MARK: - Drag & drop hacia otras apps

    private func dragProvider() -> NSItemProvider {
        switch item.kind {
        case .image, .screenshot:
            if let url = store.images.url(for: item.imagePath),
               let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
            return NSItemProvider()
        case .file:
            if let path = item.text, let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) {
                return provider
            }
            return NSItemProvider()
        default:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        }
    }

}

extension Color {
    /// Acepta #RGB, #RGBA, #RRGGBB, #RRGGBBAA.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 || s.count == 4 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
