import AppKit
import Foundation
import Vision

/// Reconocimiento de texto en imágenes con Vision. Se ejecuta fuera del hilo principal.
enum OCRService {
    @MainActor
    static func runIfEnabled(for item: ClipItem) {
        guard Prefs.ocrEnabledValue, item.kind.isImage else { return }
        let store = ClipStore.shared
        guard let url = store.images.url(for: item.imagePath) else { return }
        let id = item.id
        Task.detached(priority: .utility) {
            let text = recognize(fileURL: url)
            await MainActor.run {
                guard let text, !text.isEmpty else { return }
                ClipStore.shared.setOCR(id, text: text)
            }
        }
    }

    static func recognize(fileURL: URL) -> String? {
        guard let image = NSImage(contentsOf: fileURL),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return recognize(cgImage: cg)
    }

    static func recognize(cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["es-ES", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
