import AppKit
import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rect, ellipse, text, blur, highlight, crop

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .blur: return "eye.slash"
        case .highlight: return "highlighter"
        case .crop: return "crop"
        }
    }

    @MainActor var label: String {
        switch self {
        case .select: return L("Select")
        case .arrow: return L("Arrow")
        case .line: return L("Line")
        case .rect: return L("Rectangle")
        case .ellipse: return L("Ellipse")
        case .text: return L("Text")
        case .blur: return L("Pixelate")
        case .highlight: return L("Highlight")
        case .crop: return L("Crop")
        }
    }

    @MainActor var hint: String {
        switch self {
        case .select: return L("Click to select, drag to move, Delete to remove.")
        case .arrow, .line: return L("Drag from the start to the tip.")
        case .rect, .ellipse: return L("Drag to draw. Hold ⇧ for a square or circle.")
        case .text: return L("Click where you want to type. Enter to confirm.")
        case .blur: return L("Drag over what you want to hide (credentials, IPs, names).")
        case .highlight: return L("Drag over what you want to highlight.")
        case .crop: return L("Drag to choose the final area. Applied when saving.")
        }
    }
}

/// Una anotación en coordenadas de píxel de la imagen (origen arriba-izquierda).
struct Annotation: Identifiable {
    enum Kind { case arrow, line, rect, ellipse, text, blur, highlight }

    let id = UUID()
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""
    var fontSize: CGFloat = 28

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Rectángulo para hit-test y selección.
    var bounds: CGRect {
        switch kind {
        case .text:
            let size = textSize()
            return CGRect(x: start.x, y: start.y, width: size.width, height: size.height)
        default:
            return rect.insetBy(dx: -lineWidth, dy: -lineWidth)
        }
    }

    func textSize() -> CGSize {
        let attrs = textAttributes()
        let s = (text.isEmpty ? "Text" : text) as NSString
        let size = s.size(withAttributes: attrs)
        return CGSize(width: size.width + 12, height: size.height + 6)
    }

    func textAttributes() -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .shadow: shadow,
        ]
    }

    mutating func move(by delta: CGPoint) {
        start.x += delta.x; start.y += delta.y
        end.x += delta.x; end.y += delta.y
    }
}

/// Dibuja imagen base + anotaciones en un contexto con el eje Y hacia abajo (espacio de píxeles).
enum AnnotationRenderer {
    static func draw(base: CGImage, annotations: [Annotation], selected: UUID?, crop: CGRect?,
                     showCropOverlay: Bool, in ctx: CGContext) {
        let w = CGFloat(base.width), h = CGFloat(base.height)
        drawFlipped(base, in: CGRect(x: 0, y: 0, width: w, height: h), ctx: ctx)

        for a in annotations {
            draw(a, base: base, ctx: ctx)
        }

        if showCropOverlay, let crop {
            ctx.saveGState()
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            let full = CGPath(rect: CGRect(x: 0, y: 0, width: w, height: h), transform: nil)
            let path = CGMutablePath()
            path.addPath(full)
            path.addRect(crop)
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [8, 6])
            ctx.stroke(crop)
            ctx.restoreGState()
        }

        if let selected, let a = annotations.first(where: { $0.id == selected }) {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.stroke(a.bounds.insetBy(dx: -4, dy: -4))
            ctx.restoreGState()
        }
    }

    static func draw(_ a: Annotation, base: CGImage, ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(a.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch a.kind {
        case .line:
            ctx.move(to: a.start)
            ctx.addLine(to: a.end)
            ctx.strokePath()

        case .arrow:
            let headLength = max(14, a.lineWidth * 4.5)
            let angle = atan2(a.end.y - a.start.y, a.end.x - a.start.x)
            let tip = a.end
            let back = CGPoint(x: tip.x - headLength * cos(angle), y: tip.y - headLength * sin(angle))
            ctx.move(to: a.start)
            ctx.addLine(to: back)
            ctx.strokePath()
            let spread: CGFloat = .pi / 7
            let p1 = CGPoint(x: tip.x - headLength * cos(angle - spread), y: tip.y - headLength * sin(angle - spread))
            let p2 = CGPoint(x: tip.x - headLength * cos(angle + spread), y: tip.y - headLength * sin(angle + spread))
            ctx.move(to: tip)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.closePath()
            ctx.fillPath()

        case .rect:
            ctx.stroke(a.rect)

        case .ellipse:
            ctx.strokeEllipse(in: a.rect)

        case .highlight:
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(a.color.withAlphaComponent(0.45).cgColor)
            ctx.fill(a.rect)

        case .blur:
            let r = a.rect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
            guard r.width >= 2, r.height >= 2, let patch = base.cropping(to: r) else { return }
            let factor = max(6, Int(min(r.width, r.height) / 8))
            let smallW = max(1, Int(r.width) / factor), smallH = max(1, Int(r.height) / factor)
            if let small = CGContext(data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                small.interpolationQuality = .medium
                small.draw(patch, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
                if let pixelated = small.makeImage() {
                    ctx.interpolationQuality = .none
                    drawFlipped(pixelated, in: r, ctx: ctx)
                }
            }

        case .text:
            let attrs = a.textAttributes()
            let s = (a.text.isEmpty ? "Text" : a.text) as NSString
            s.draw(at: CGPoint(x: a.start.x + 6, y: a.start.y + 3), withAttributes: attrs)
        }
    }

    /// Dibuja un CGImage en un contexto con Y hacia abajo sin que salga invertido.
    static func drawFlipped(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    /// Imagen final en píxeles, con recorte aplicado.
    static func render(base: CGImage, annotations: [Annotation], crop: CGRect?) -> CGImage? {
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let out = (crop?.integral.intersection(full)).flatMap { $0.isEmpty ? nil : $0 } ?? full
        guard let ctx = CGContext(data: nil, width: Int(out.width), height: Int(out.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: out.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -out.minX, y: -out.minY)

        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        draw(base: base, annotations: annotations, selected: nil, crop: nil, showCropOverlay: false, in: ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
