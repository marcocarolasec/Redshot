import AppKit
import Combine
import Foundation

/// Fuente de verdad para la UI. Envuelve la base de datos y el almacén de imágenes.
@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var apps: [(bundle: String, name: String)] = []
    @Published var search: String = "" { didSet { reload() } }
    @Published var kindFilter: ClipKind? = nil { didSet { reload() } }
    @Published var appFilter: String? = nil { didSet { reload() } }
    @Published private(set) var lastError: String?

    let db: Database
    let images: ImageStore
    let rootDirectory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDirectory = support.appendingPathComponent("Redshot", isDirectory: true)
        ClipStore.migrateLegacyDirectoryIfNeeded(support: support, to: rootDirectory)
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        images = ImageStore(directory: rootDirectory.appendingPathComponent("images", isDirectory: true))
        do {
            db = try Database(path: rootDirectory.appendingPathComponent("redshot.sqlite").path)
        } catch {
            fatalError("No se pudo abrir la base de datos: \(error)")
        }
        reload()
    }

    /// Versiones anteriores guardaban en "SnapVault". Se mueve una sola vez.
    private static func migrateLegacyDirectoryIfNeeded(support: URL, to dest: URL) {
        let fm = FileManager.default
        let legacy = support.appendingPathComponent("SnapVault", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: dest.path) else { return }
        do {
            try fm.moveItem(at: legacy, to: dest)
            for ext in ["", "-wal", "-shm"] {
                let old = dest.appendingPathComponent("snapvault.sqlite" + ext)
                let new = dest.appendingPathComponent("redshot.sqlite" + ext)
                if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: new) }
            }
        } catch {
            NSLog("Redshot: no se pudo migrar el directorio antiguo: \(error)")
        }
    }

    // MARK: - Lectura

    func reload() {
        do {
            items = try db.fetch(search: search, kind: kindFilter, bundle: appFilter, limit: 500)
            apps = try db.distinctApps()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    func reportError(_ message: String) {
        lastError = message
    }

    func recent(_ n: Int) -> [ClipItem] {
        (try? db.recent(limit: n)) ?? []
    }

    // MARK: - Alta

    @discardableResult
    func addText(_ text: String, kind: ClipKind, source: SourceApp) -> ClipItem? {
        let hash = ImageStore.hash(kind.rawValue + "|" + text)
        if let existing = dedupe(hash: hash, source: source) { return existing }
        let item = ClipItem(kind: kind, text: text, source: source, contentHash: hash)
        return persist(item)
    }

    @discardableResult
    func addFile(_ url: URL, source: SourceApp) -> ClipItem? {
        addText(url.path, kind: .file, source: source)
    }

    @discardableResult
    func addImage(pngData: Data, kind: ClipKind, source: SourceApp) -> ClipItem? {
        let hash = ImageStore.hash(pngData)
        if let existing = dedupe(hash: hash, source: source) { return existing }
        do {
            let saved = try images.savePNG(pngData)
            let item = ClipItem(kind: kind, imagePath: saved.image, thumbPath: saved.thumb,
                                source: source, contentHash: hash)
            return persist(item)
        } catch {
            lastError = "Could not save image: \(error)"
            return nil
        }
    }

    private func dedupe(hash: String, source: SourceApp) -> ClipItem? {
        guard let existing = try? db.findByHash(hash) else { return nil }
        try? db.touch(id: existing.id, source: source)
        reload()
        return existing
    }

    private func persist(_ item: ClipItem) -> ClipItem? {
        do {
            try db.insert(item)
            NSLog("Redshot: guardado \(item.kind.rawValue) desde \(item.sourceAppName ?? "?")")
            prune()
            reload()
            return item
        } catch {
            lastError = "Could not save: \(error)"
            return nil
        }
    }

    private func prune() {
        guard let overflow = try? db.overflow(keep: Prefs.maxItemsValue) else { return }
        for old in overflow {
            images.delete([old.imagePath, old.thumbPath])
            try? db.delete(id: old.id)
        }
    }

    // MARK: - Edición

    func togglePin(_ item: ClipItem) {
        try? db.setPinned(id: item.id, !item.pinned)
        reload()
    }

    func setOCR(_ id: String, text: String?) {
        try? db.setOCR(id: id, text: text)
        reload()
    }

    func setCategory(_ item: ClipItem, _ category: String?) {
        try? db.setCategory(id: item.id, category: category?.isEmpty == true ? nil : category)
        reload()
    }

    func delete(_ item: ClipItem) {
        images.delete([item.imagePath, item.thumbPath])
        try? db.delete(id: item.id)
        reload()
    }

    func clearUnpinned() {
        guard let all = try? db.allUnpinned() else { return }
        for it in all {
            images.delete([it.imagePath, it.thumbPath])
            try? db.delete(id: it.id)
        }
        reload()
    }

    func image(for item: ClipItem) -> NSImage? {
        guard let url = images.url(for: item.imagePath) else { return nil }
        return NSImage(contentsOf: url)
    }
}
