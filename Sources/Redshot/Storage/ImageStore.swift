import AppKit
import CryptoKit
import Foundation

/// Guarda imágenes (PNG) y miniaturas en disco. La base de datos solo referencia nombres de fichero.
final class ImageStore {
    let directory: URL
    let thumbsDirectory: URL

    init(directory: URL) {
        self.directory = directory
        self.thumbsDirectory = directory.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbsDirectory, withIntermediateDirectories: true)
    }

    func url(for name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return directory.appendingPathComponent(name)
    }

    /// Guarda datos PNG y genera miniatura. Devuelve los nombres relativos.
    func savePNG(_ data: Data) throws -> (image: String, thumb: String?) {
        let base = ISO8601DateFormatter.fileSafeStamp() + "-" + String(UUID().uuidString.prefix(8))
        let imageName = base + ".png"
        try data.write(to: directory.appendingPathComponent(imageName), options: .atomic)

        var thumbName: String?
        if let thumb = makeThumbnail(from: data, maxSide: 480) {
            thumbName = "thumbs/" + base + "-thumb.png"
            try? thumb.write(to: directory.appendingPathComponent(thumbName!), options: .atomic)
        }
        return (imageName, thumbName)
    }

    func delete(_ names: [String?]) {
        for case let name? in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: - Conversión

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    func makeThumbnail(from data: Data, maxSide: CGFloat) -> Data? {
        guard let source = NSImage(data: data), source.size.width > 0, source.size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(source.size.width, source.size.height))
        let target = NSSize(width: max(1, source.size.width * scale), height: max(1, source.size.height * scale))
        let thumb = NSImage(size: target, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
            return true
        }
        return ImageStore.pngData(from: thumb)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ string: String) -> String {
        hash(Data(string.utf8))
    }
}

private extension ISO8601DateFormatter {
    static func fileSafeStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
