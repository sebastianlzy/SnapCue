import AppKit
import Carbon
import CoreGraphics

@MainActor
final class SnapCueApp: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let picker = RegionPicker()
    private var editor: Editor?
    private var selecting = false
    private var capturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.status = status
        status.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SnapCue")
        let menu = NSMenu()
        let capture = menu.addItem(withTitle: "Capture Region", action: #selector(startCapture), keyEquivalent: "")
        capture.target = self
        let show = menu.addItem(withTitle: "Show Editor", action: #selector(showEditor), keyEquivalent: "")
        show.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SnapCue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        if registerHotKey() {
            capture.title = "Capture Region (⌃⌥⌘4)"
        } else {
            let note = NSMenuItem(title: "Capture shortcut unavailable", action: nil, keyEquivalent: "")
            menu.insertItem(note, at: 1)
        }

        let mainMenu = NSMenu()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func registerHotKey() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated {
                (NSApp.delegate as? SnapCueApp)?.startCapture()
            }
            return noErr
        }, 1, &event, nil, &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: 0x534E4150, id: 1)
        return RegisterEventHotKey(UInt32(kVK_ANSI_4), UInt32(controlKey | optionKey | cmdKey),
                                   id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    @objc private func startCapture() {
        guard !selecting, !capturing else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            showPermissionHelp()
            return
        }
        guard !NSScreen.screens.isEmpty else { return }
        selecting = true
        NSApp.activate()
        picker.show(onSelection: { [weak self] screen, start, end in
            self?.finishSelection(screen: screen, start: start, end: end)
        }, onCancel: { [weak self] in
            self?.picker.close()
            self?.selecting = false
        })
    }

    private func finishSelection(screen: NSScreen, start: CGPoint, end: CGPoint) {
        picker.close()
        selecting = false
        capturing = true
        Task {
            defer { capturing = false }
            do {
                guard let image = try await ScreenCapture.region(on: screen, from: start, to: end) else { return }
                editor?.close()
                editor = Editor(image: image)
                showEditor()
            } catch {
                if CGPreflightScreenCaptureAccess() {
                    showAlert("Capture failed", detail: error.localizedDescription)
                } else {
                    showPermissionHelp()
                }
            }
        }
    }

    @objc private func showEditor() {
        guard let editor else { return }
        NSApp.activate()
        editor.showWindow(nil)
        editor.window?.makeKeyAndOrderFront(nil)
    }

    private func showPermissionHelp() {
        showAlert("Allow screen capture for SnapCue",
                  detail: "In System Settings, open Privacy & Security → Screen & System Audio Recording. Enable SnapCue, then reopen the app and try again.")
    }

    private func showAlert(_ title: String, detail: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = SnapCueApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
