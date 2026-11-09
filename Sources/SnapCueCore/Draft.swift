import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum Mark {
    case arrow(CGPoint, CGPoint)
    case label(CGPoint, String)
}

@MainActor
public struct Draft {
    public let image: CGImage
    public var marks: [Mark] = []

    public init(image: CGImage) { self.image = image }

    public var size: CGSize { CGSize(width: image.width, height: image.height) }

    /// Draw into a flipped AppKit graphics context in document pixels.
    public func draw(in bounds: CGRect, preview: Mark? = nil) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()

        let transform = NSAffineTransform()
        transform.translateX(by: bounds.minX, yBy: bounds.minY)
        transform.scaleX(by: bounds.width / size.width, yBy: bounds.height / size.height)
        transform.concat()

        NSImage(cgImage: image, size: size).draw(
            in: CGRect(origin: .zero, size: size), from: .zero,
            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
        )

        let unit = max(1, min(size.width, size.height) / 160)
        for mark in marks { draw(mark, unit: unit) }
        if let preview { draw(preview, unit: unit) }
    }

    private func draw(_ mark: Mark, unit: CGFloat) {
        switch mark {
        case let .arrow(start, end):
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0 else { return }
            let head = min(5 * unit, length * 0.45)
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: end)
                path.line(to: CGPoint(
                    x: end.x - head * cos(angle + offset),
                    y: end.y - head * sin(angle + offset)
                ))
            }
            path.lineCapStyle = .round
            path.lineWidth = 2.8 * unit
            NSColor.white.setStroke()
            path.stroke()
            path.lineWidth = 1.6 * unit
            NSColor.systemRed.setStroke()
            path.stroke()
        case let .label(point, text):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 8 * unit + 8),
                .foregroundColor: NSColor.white
            ]
            let label = NSAttributedString(string: text, attributes: attributes)
            let padding = 3 * unit
            let measured = label.size()
            let box = CGSize(width: measured.width + 2 * padding, height: measured.height + 2 * padding)
            let origin = CGPoint(x: min(point.x, max(0, size.width - box.width)),
                                 y: min(point.y, max(0, size.height - box.height)))
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: CGRect(origin: origin, size: box),
                         xRadius: padding, yRadius: padding).fill()
            label.draw(at: CGPoint(x: origin.x + padding, y: origin.y + padding))
        }
    }

    public func png() -> Data? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        let data = NSMutableData()
        guard let flattened = context.makeImage(),
              let output = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(output, flattened, nil)
        return CGImageDestinationFinalize(output) ? data as Data : nil
    }
}
