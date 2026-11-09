import AppKit
import SnapCueCore

@MainActor
final class Editor: NSWindowController {
    private let canvas: Canvas

    init(image: CGImage) {
        let canvas = Canvas(draft: Draft(image: image))
        self.canvas = canvas
        let tools = NSSegmentedControl(labels: ["Arrow", "Label", "Select"], trackingMode: .selectOne,
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
        window.isMovableByWindowBackground = true
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
    private enum Tool: Int { case arrow, label, select }
    private var tool = Tool.arrow
    private var movingIndex: Int?
    private var start: CGPoint?
    private var preview: Mark?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

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
        var displayed = draft
        if let movingIndex, let preview {
            displayed.marks[movingIndex] = preview
        }
        displayed.draw(in: imageBounds, preview: movingIndex == nil ? preview : nil)
    }

    @objc func selectTool(_ sender: NSSegmentedControl) {
        tool = Tool(rawValue: sender.selectedSegment) ?? .arrow
    }

    override func mouseDown(with event: NSEvent) {
        guard imageBounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        let point = documentPoint(event)
        switch tool {
        case .label:
            promptForLabel(at: point)
        case .arrow:
            start = point
        case .select:
            let tolerance = 5 * draft.size.width / imageBounds.width
            movingIndex = draft.markIndex(at: point, tolerance: tolerance)
            if movingIndex != nil { start = point }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        preview = mark(at: documentPoint(event), from: start)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let end = documentPoint(event)
        if start != end {
            let mark = mark(at: end, from: start)
            if let movingIndex {
                draft.marks[movingIndex] = mark
            } else {
                draft.marks.append(mark)
            }
        }
        self.start = nil
        movingIndex = nil
        preview = nil
        needsDisplay = true
    }

    private func mark(at end: CGPoint, from start: CGPoint) -> Mark {
        if let movingIndex {
            return draft.movedMark(at: movingIndex, by: CGPoint(x: end.x - start.x, y: end.y - start.y))
        }
        return .arrow(start, end)
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
