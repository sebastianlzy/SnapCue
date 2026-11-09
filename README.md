# SnapCue

A macOS menu bar app for capturing a region, marking it up, and copying a PNG.

Build with Swift 6 and the macOS SDK, then open the locally signed app.

```sh
sh build-app.sh
open dist/SnapCue.app
```

Choose **Capture Region** in the launch window or from the viewfinder menu bar icon, or press Control–Option–Command–4. Allow screen recording in System Settings when prompted. Drag on one display to capture an area, or press Escape to cancel. In the editor, drag with **Arrow** selected, or choose **Label** and click the image. Choose **Select** and drag an existing arrow or label to move it. Drag the title bar or empty space above the canvas to move the editor window. Use **Copy PNG** to paste the result into another app.

Run the automated checks with `swift test`. See the [first workflow spec](docs/specs/001-capture-to-clipboard.md) and the [implementation plan](docs/implementation-plan.md).
