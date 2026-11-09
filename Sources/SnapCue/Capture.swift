import AppKit
import ScreenCaptureKit
import SnapCueCore

@MainActor
final class RegionPicker {
    private var panels: [NSPanel] = []

    func show(onSelection: @escaping (NSScreen, CGPoint, CGPoint) -> Void, onCancel: @escaping () -> Void) {
        for screen in NSScreen.screens {
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless],
                                       backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = false
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.setFrame(screen.frame, display: false)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onSelection = { start, end in onSelection(screen, start, end) }
            view.onCancel = onCancel
            panel.contentView = view
            panel.initialFirstResponder = view
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) {
                panel.makeKey()
                panel.makeFirstResponder(view)
            }
        }
    }

    func close() {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onSelection: ((CGPoint, CGPoint) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var end: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        end = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        end = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        onSelection?(start, convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "\u{1b}" {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let start, let end, let selection = Region.pixels(
            from: start, to: end, display: bounds.size, bitmap: bounds.size
        ) else { return }
        NSColor.white.withAlphaComponent(0.18).setFill()
        selection.fill()
        NSColor.white.setStroke()
        NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

@MainActor
enum ScreenCapture {
    enum Failure: LocalizedError {
        case displayUnavailable, cropFailed, imageTooLarge

        var errorDescription: String? {
            switch self {
            case .displayUnavailable: "The selected display is no longer available. Try another capture."
            case .cropFailed: "SnapCue couldn’t read the selected pixels. Try another capture."
            case .imageTooLarge: "The display is too large to capture. Try a lower display resolution."
            }
        }
    }

    static func region(on screen: NSScreen, from start: CGPoint, to end: CGPoint) async throws -> CGImage? {
        let size = screen.frame.size
        guard Region.pixels(from: start, to: end, display: size, bitmap: size) != nil else { return nil }
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw Failure.displayUnavailable
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == id.uint32Value }) else {
            throw Failure.displayUnavailable
        }

        let ownApplication = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplication, exceptingWindows: [])
        let width = Int((size.width * screen.backingScaleFactor).rounded())
        let height = Int((size.height * screen.backingScaleFactor).rounded())
        guard width > 0, height > 0, width <= 64_000_000 / height else { throw Failure.imageTooLarge }
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let rect = Region.pixels(from: start, to: end, display: size,
                                       bitmap: CGSize(width: image.width, height: image.height)),
              let cropped = image.cropping(to: rect)
        else { throw Failure.cropFailed }
        return cropped
    }
}
