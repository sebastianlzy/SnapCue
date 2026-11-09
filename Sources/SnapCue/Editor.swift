import AppKit
import SnapCueCore

@MainActor
final class Editor: NSWindowController {
    private let canvas: Canvas

    init(image: CGImage) {
        let canvas = Canvas(draft: Draft(image: image))
        self.canvas = canvas
        let tools = NSSegmentedControl(labels: ["Arrow", "Label"], trackingMode: .selectOne,
                                       target: nil, action: nil)
        tools.selectedSegment = 0
        tools.setAccessibilityLabel("Markup tool")
        let copy = NSButton(title: "Copy PNG", target: nil, action: nil)
        copy.keyEquivalent = "\r"
        let bar = NSStackView(views: [tools, copy])
        bar.spacing = 12
        let content = NSView()
        for view in [bar, canvas] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            canvas.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SnapCue"
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 320, height: 240)
        window.contentView = content
        window.center()
        super.init(window: window)
        tools.target = canvas
        tools.action = #selector(Canvas.selectTool(_:))
        copy.target = self
        copy.action = #selector(copyPNG(_:))
    }

    required init?(coder: NSCoder) { nil }

    @objc func copyPNG(_ sender: Any?) {
        guard let png = canvas.draft.png() else {
            showCopyError()
            return
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            showCopyError()
            return
        }
        NSAccessibility.post(element: canvas, notification: .announcementRequested,
                             userInfo: [.announcement: "PNG copied", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func showCopyError() {
        let alert = NSAlert()
        alert.messageText = "Couldn’t copy the screenshot"
        alert.informativeText = "Try copying again."
        if let window { alert.beginSheetModal(for: window) }
    }
}

private final class Canvas: NSView {
    var draft: Draft
    private var isLabelTool = false
    private var start: CGPoint?
    private var preview: Mark?
    override var isFlipped: Bool { true }

    init(draft: Draft) {
        self.draft = draft
        super.init(frame: .zero)
        setAccessibilityLabel("Screenshot canvas")
    }

    required init?(coder: NSCoder) { nil }

    private var imageBounds: CGRect {
        let available = bounds.insetBy(dx: 12, dy: 12)
        let scale = min(available.width / draft.size.width, available.height / draft.size.height)
        guard scale > 0 else { return .zero }
        let size = CGSize(width: draft.size.width * scale, height: draft.size.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let imageBounds = imageBounds
        guard !imageBounds.isEmpty else { return }
        draft.draw(in: imageBounds, preview: preview)
    }

    @objc func selectTool(_ sender: NSSegmentedControl) {
        isLabelTool = sender.selectedSegment == 1
    }

    override func mouseDown(with event: NSEvent) {
        guard imageBounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        let point = documentPoint(event)
        if isLabelTool {
            promptForLabel(at: point)
        } else {
            start = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        preview = .arrow(start, documentPoint(event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let end = documentPoint(event)
        if start != end { draft.marks.append(.arrow(start, end)) }
        self.start = nil
        preview = nil
        needsDisplay = true
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        let image = imageBounds
        return CGPoint(
            x: min(max(0, (point.x - image.minX) / image.width * draft.size.width), draft.size.width),
            y: min(max(0, (point.y - image.minY) / image.height * draft.size.height), draft.size.height)
        )
    }

    private func promptForLabel(at point: CGPoint) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Add a label"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: CGRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "Label text"
        input.setAccessibilityLabel("Label text")
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: window) { [weak self] response in
            let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let self, response == .alertFirstButtonReturn, !text.isEmpty else { return }
            self.draft.marks.append(.label(point, text))
            self.needsDisplay = true
        }
    }
}
