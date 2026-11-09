# 001 Capture to clipboard

This is the first slice of CAP-01, EDT-01, and OUT-01 in the [implementation plan](../implementation-plan.md).

- From the menu bar or the default Control–Option–Command–4 shortcut, select a region on one display. The selection is confined to the display where the drag starts. The captured image contains the selected native pixels and excludes SnapCue windows.
- Normalize the drag direction and clip to the starting display. Convert the selection to pixels by rounding its minimum edges down and its maximum edges up. A zero-width or zero-height drag and Escape cancel. A cancelled or failed capture keeps the current draft. If screen recording access is denied, explain how to grant access and retry.
- Open the capture in the editor. Choose Arrow and drag to draw one, or choose Label and click to enter text. Draw additional marks in insertion order. Closing the editor keeps the current draft available from the menu bar. A successful capture replaces the current draft.
- Copy exports a flattened PNG at the capture's pixel dimensions. Pasting into a PNG-aware app includes both marks. Preview and export use the same drawing code.

Acceptance checks cover a reverse drag, cancellation, a drag at the edge of a scaled display, and copying a fixture with an arrow and label. Generated cases check that reversing a drag preserves the selection and every accepted rectangle stays within the display. Real capture, permission recovery, and paste into a second app also need a desktop smoke check.
