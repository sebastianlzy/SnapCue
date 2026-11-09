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

        for mark in marks { draw(mark) }
        if let preview { draw(preview) }
    }

    private var unit: CGFloat { max(1, min(size.width, size.height) / 160) }

    public func markIndex(at point: CGPoint, tolerance: CGFloat) -> Int? {
        marks.indices.reversed().first { index in
            switch marks[index] {
            case let .arrow(start, end):
                return arrowSegments(from: start, to: end).contains { a, b in
                    let dx = b.x - a.x
                    let dy = b.y - a.y
                    let lengthSquared = dx * dx + dy * dy
                    guard lengthSquared > 0 else { return false }
                    let fraction = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
                    return hypot(point.x - a.x - fraction * dx, point.y - a.y - fraction * dy)
                        <= 1.4 * unit + tolerance
                }
            case let .label(origin, text):
                return labelLayout(at: origin, text: text).box.contains(point)
            }
        }
    }

    public func movedMark(at index: Int, by delta: CGPoint) -> Mark {
        func translate(_ point: CGPoint, within bounds: CGRect) -> CGPoint {
            let dx = min(max(delta.x, -bounds.minX), max(0, size.width - bounds.maxX))
            let dy = min(max(delta.y, -bounds.minY), max(0, size.height - bounds.maxY))
            return CGPoint(x: point.x + dx, y: point.y + dy)
        }

        switch marks[index] {
        case let .arrow(start, end):
            let points = arrowSegments(from: start, to: end).flatMap { [$0.0, $0.1] }
            let left = points.map(\.x).min() ?? start.x
            let top = points.map(\.y).min() ?? start.y
            let right = points.map(\.x).max() ?? start.x
            let bottom = points.map(\.y).max() ?? start.y
            let bounds = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            return .arrow(translate(start, within: bounds), translate(end, within: bounds))
        case let .label(origin, text):
            let box = labelLayout(at: origin, text: text).box
            return .label(translate(box.origin, within: box), text)
        }
    }

    private func arrowSegments(from start: CGPoint, to end: CGPoint) -> [(CGPoint, CGPoint)] {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return [] }
        let head = min(5 * unit, length * 0.45)
        return [(start, end)] + [-CGFloat.pi / 6, CGFloat.pi / 6].map { offset in
            (end, CGPoint(x: end.x - head * cos(angle + offset),
                          y: end.y - head * sin(angle + offset)))
        }
    }

    private func labelLayout(at point: CGPoint, text: String) -> (label: NSAttributedString, box: CGRect) {
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 8 * unit + 8),
            .foregroundColor: NSColor.white
        ])
        let padding = 3 * unit
        let measured = label.size()
        let box = CGSize(width: measured.width + 2 * padding, height: measured.height + 2 * padding)
        let origin = CGPoint(x: min(point.x, max(0, size.width - box.width)),
                             y: min(point.y, max(0, size.height - box.height)))
        return (label, CGRect(origin: origin, size: box))
    }

    private func draw(_ mark: Mark) {
        switch mark {
        case let .arrow(start, end):
            let path = NSBezierPath()
            for (a, b) in arrowSegments(from: start, to: end) {
                path.move(to: a)
                path.line(to: b)
            }
            path.lineCapStyle = .round
            path.lineWidth = 2.8 * unit
            NSColor.white.setStroke()
            path.stroke()
            path.lineWidth = 1.6 * unit
            NSColor.systemRed.setStroke()
            path.stroke()
        case let .label(point, text):
            let (label, box) = labelLayout(at: point, text: text)
            let padding = 3 * unit
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: box, xRadius: padding, yRadius: padding).fill()
            label.draw(at: CGPoint(x: box.minX + padding, y: box.minY + padding))
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
