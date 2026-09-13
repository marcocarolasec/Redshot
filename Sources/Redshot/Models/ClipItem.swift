import AppKit
import Foundation

enum ClipKind: String, CaseIterable, Identifiable {
    case text, link, code, color, image, file, screenshot

    var id: String { rawValue }

    @MainActor var label: String {
        switch self {
        case .text: return L("Text")
        case .link: return L("Link")
        case .code: return L("Code")
        case .color: return L("Color")
        case .image: return L("Image")
        case .file: return L("File")
        case .screenshot: return L("Screenshot")
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file: return "doc"
        case .screenshot: return "camera.viewfinder"
        }
    }

    var isImage: Bool { self == .image || self == .screenshot }
}

struct SourceApp {
    var name: String?
    var bundleID: String?

    static var frontmost: SourceApp {
        let app = NSWorkspace.shared.frontmostApplication
        return SourceApp(name: app?.localizedName, bundleID: app?.bundleIdentifier)
    }
}

struct ClipItem: Identifiable, Hashable {
    let id: String
    var kind: ClipKind
    var text: String?
    var imagePath: String?
    var thumbPath: String?
    var ocrText: String?
    var sourceAppName: String?
    var sourceBundleID: String?
    var createdAt: Date
    var pinned: Bool
    var category: String?
    var contentHash: String

    init(
        id: String = UUID().uuidString,
        kind: ClipKind,
        text: String? = nil,
        imagePath: String? = nil,
        thumbPath: String? = nil,
        ocrText: String? = nil,
        source: SourceApp = SourceApp(),
        createdAt: Date = Date(),
        pinned: Bool = false,
        category: String? = nil,
        contentHash: String
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.thumbPath = thumbPath
        self.ocrText = ocrText
        self.sourceAppName = source.name
        self.sourceBundleID = source.bundleID
        self.createdAt = createdAt
        self.pinned = pinned
        self.category = category
        self.contentHash = contentHash
    }

    init?(row: [String: Any]) {
        guard let id = row["id"] as? String,
              let kindRaw = row["kind"] as? String,
              let kind = ClipKind(rawValue: kindRaw),
              let created = row["created_at"] as? Double,
              let hash = row["content_hash"] as? String else { return nil }
        self.id = id
        self.kind = kind
        self.text = row["text"] as? String
        self.imagePath = row["image_path"] as? String
        self.thumbPath = row["thumb_path"] as? String
        self.ocrText = row["ocr_text"] as? String
        self.sourceAppName = row["source_app"] as? String
        self.sourceBundleID = row["source_bundle"] as? String
        self.createdAt = Date(timeIntervalSince1970: created)
        self.pinned = (row["pinned"] as? Int ?? 0) != 0
        self.category = row["category"] as? String
        self.contentHash = hash
    }

    /// Texto que se muestra en la tarjeta o en el menú de acceso rápido.
    @MainActor var preview: String {
        switch kind {
        case .image: return ocrText.flatMap { $0.isEmpty ? nil : $0 } ?? L("Image")
        case .screenshot: return ocrText.flatMap { $0.isEmpty ? nil : $0 } ?? L("Screenshot")
        case .file: return URL(fileURLWithPath: text ?? "").lastPathComponent
        default: return text ?? ""
        }
    }

    @MainActor var menuTitle: String {
        let flat = preview.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > 60 ? String(flat.prefix(60)) + "…" : flat
    }
}
