# SnapCue implementation plan

Status: proposed v0.1 specification and delivery plan.

SnapCue is a native macOS menu bar app for turning a screenshot into visual feedback. The first release targets bug reports, design reviews, and support instructions. The defining scenario is to capture a region, draw an arrow, add a label, and paste the result into a ticket without saving a file first.

## Scope and initial decisions

- Ship region, window, and display capture, plus PNG/JPEG import. Include arrows, labels, rectangles, ellipses, pen, highlighter, stamps, crop, canvas expansion, pixelation, and solid redaction.
- Support clipboard copy, PNG/JPEG export, drag-out, and the macOS share sheet. Keep drafts in memory for v0.1. Show a discard confirmation when closing a draft with edits. Keep the workflow local and account-free.
- Defer scrolling capture, recording, OCR, PDF markup, cloud sync, and persistent editable documents.
- Use macOS 14 as the provisional minimum, Swift, a SwiftUI shell with AppKit integration, and ScreenCaptureKit for still capture. Verify the minimum OS, real capture permission behavior, and hotkey registration in the first milestone before committing to a deployment target. Test distribution signing and capture access in the beta build before selecting the release channel. [Apple ScreenCaptureKit documentation](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)

## Specification-driven workflow

Treat the requirement IDs below as the initial source of truth. For each milestone, extract its contracts into a numbered spec under `docs/specs/` before implementing them. Each spec records user scenarios, state transitions, error behavior, invariants, acceptance cases, and explicit exclusions. Keep IDs stable. When behavior changes, update the spec and its tests in the same pull request.

For each requirement, write one representative acceptance example and add generated properties wherever there is a meaningful invariant. Show the test catching missing or incorrect behavior, implement the smallest complete slice, then refactor with the checks passing. Each implementation PR links its requirement IDs, checks, and any manual evidence. Use requirement IDs in test names or tags so reviewers can trace the spec to evidence.

## Behavior contracts and acceptance cases

| ID | Contract | Representative acceptance case |
| --- | --- | --- |
| CAP-01 | Open region capture from the menu or a configurable hotkey. A region is confined to the display where the drag starts. Clamp the selection to that display and use its native pixel scale. Esc or zero area cancels without opening or replacing a draft. | Drag in reverse near the edge of a 2× display beside a 1× display. The resulting image contains only the selected pixels on the starting display and excludes SnapCue's selection overlay. |
| CAP-02 | Capture a user-selected window or display. Handle permission denial, a removed display, or a window that closes with an actionable error and a path to retry. Ignore late results from cancelled requests. Allow one active capture at a time. | Deny permission, retry after granting it, then remove the selected source during another capture. A previous draft stays open throughout. |
| CAP-03 | Import valid PNG and JPEG from the file picker or by dropping onto the editor. Normalize orientation at decode. Report invalid files and oversized images without changing the active draft. | Drop an oriented JPEG, then a truncated PNG. The JPEG opens upright and remains available after the PNG error. |
| EDT-01 | Create arrows, text, rectangles, ellipses, freehand paths, highlights, and stamps. Select, move, resize where applicable, delete, and change color or stroke. Later objects render above earlier objects. Drag previews commit as one action on release. | Add an arrow, drag it, change its color, then undo once. Only the color change is reversed. |
| EDT-02 | Maintain ordered undo and redo for document edits. A new committed edit clears redo. Cancellation, selection, and zoom leave history intact. | Undo two edits, change zoom, redo one, and make a new edit. Redo is then unavailable. |
| EDT-03 | Crop to a nonempty canvas rectangle and allow explicit expansion to make room for callouts. Preserve source and mark positions in document space. Clip output to the current canvas. | Crop across an arrow, undo, and expand the canvas. The original arrow returns and retains its alignment with the screenshot. |
| EDT-04 | Pixelation is a visual effect. Solid redaction is an opaque final pass over the selected area, including any overlapping annotations. Preview and shared output apply the same mask. | Place a redaction across an arrow and text on a patterned source. Decoded PNG output contains only the chosen fill inside the mask. |
| OUT-01 | Render a flattened snapshot of the current document. Copy lossless output to the clipboard and export PNG or JPEG. PNG preserves transparency. JPEG composites onto white. Export failures preserve the draft and undo history. | Copy a crop to the clipboard, save PNG, and decode both. Dimensions and normalized pixels match. A failed save leaves the last successful output and the current draft available. |
| OUT-02 | Drag-out and the share sheet use the same flattened renderer. Each action captures its own immutable revision and shares only that revision's output. | Start a drag, then edit the draft. The dragged file still contains the revision captured when the drag began. |
| UX-01 | Make capture, tool selection, undo, redo, and copy accessible by keyboard. Provide accessible labels and visible focus. Explain how to recover from permission denial and report hotkey conflicts. | Use the keyboard to switch tools and copy a draft. Verify menu and toolbar labels with VoiceOver and recover from denied access. |

## Architecture and data rules

- **App shell** owns the menu, hotkeys, windows, focus, and permission messaging. A capture coordinator serializes capture sessions and ignores stale callbacks by request ID. ScreenCaptureKit sits behind a capture interface so tests can drive success, denial, cancellation, and late results.
- **Editor core** owns an immutable source bitmap reference, canvas bounds, and ordered annotations with stable IDs. It reduces typed edits to document states and maintains bounded undo and redo. Treat selection, zoom, and uncommitted gestures as view state. Keep large bitmaps shared across revisions.
- **Geometry** converts display points to display-local pixels, then works in document space with a top-left origin. Normalize drag direction, intersect with the starting display, round minimum edges down and maximum edges up, and clamp again to pixel bounds. Represent raster bounds as half-open integer rectangles. Keep view transforms separate so zoom and pan never alter export dimensions.
- **Renderer** composites the source and regular marks in order, clips to the canvas, and applies opaque redactions last. Use the same drawing pipeline for preview and output. The clipboard, file, drag, and share adapters receive only flattened output. Strip imported metadata and use a normalized color space for lossless comparisons. Write files atomically and release temporary share files after handoff completes or the next launch.
- **Resource limits** are proposed defaults of 64 megapixels per source or canvas and 50 undo steps. Check dimensions and arithmetic before allocating. Validate the limits on real large captures in the first milestone. Run capture, decode, and full-size export away from UI work while keeping UI state changes on the main actor.

## Property-based testing

Use Swift Testing as the runner. In the first milestone, implement a small test-only harness for deterministic generation, replay, and shrinking. Apple’s parameterized tests can expose seeds as individual test arguments. Each property has a named generator and an oracle that does not call the implementation under test. Use small edge-heavy fixtures for raster checks. Keep platform API behavior in integration and manual checks. [Apple Swift Testing documentation](https://developer.apple.com/documentation/testing/parameterizedtesting)

| Property | Generated cases | Check |
| --- | --- | --- |
| P-CAP-GEOMETRY (CAP-01) | Negative display origins, adjacent displays, 1× and 2× scale, fractional points, reversed drags, edges, zero area | Reverse endpoints and get the same selection. Valid raster rectangles stay inside the starting display. Compare pixel coverage on small grids against independent per-pixel intersection. Reject empty intersections. |
| P-CAP-STATE (CAP-02) | Start, cancel, retry, permission changes, source changes, reordered completions | Compare with a small reference state machine. Only the active request can create a draft. A failed or cancelled request preserves existing drafts. |
| P-INPUT-BOUNDS (CAP-03, EDT-03) | Dimensions near limits, arithmetic overflow, truncated data, off-canvas and empty rectangles | Return a defined error without publishing partial state. Accepted dimensions stay within the pixel budget. |
| P-HISTORY (EDT-01, EDT-02, EDT-03) | Sequences of adds, moves, deletes, crop, expand, undo, redo, and view changes | Compare with a reference list of committed snapshots. Undo restores the preceding state within the history bound. Redo restores the next state. A new edit drops redo. View changes never add history. |
| P-CROP (EDT-03) | Tiny images with unique pixel IDs, arbitrary crop/expand rectangles, edge-aligned marks | With plain images, decoded output equals the corresponding region of the reference grid. Expanding adds transparent padding without moving document-space content. |
| P-REDACTION (EDT-04, OUT-01, OUT-02) | Distinct source patterns that differ only beneath the mask, overlapping marks, multiple masks, crops | For lossless output, masked pixels are opaque fill and unmasked pixels match the baseline render. Two otherwise identical drafts differing only beneath the mask yield the same normalized flattened pixels. JPEG comparisons use the same already-redacted input and allow codec loss when checking decoded colors. |
| P-EXPORT (OUT-01, OUT-02) | Tiny documents with alpha, arbitrary valid canvas dimensions, interleaved edits and snapshot requests | Each lossless adapter returns the same decoded dimensions and pixels for a given revision. Changes after a snapshot cannot affect its output. Check JPEG dimensions and white compositing with controlled fixtures. |

Bias generators toward one-pixel images, exact boundaries, repeated operations, and degenerate inputs. Generate valid and invalid cases explicitly so discarded samples cannot hide a missing branch. Shrink failures by reducing operation lists, coordinates, and fixture size while retaining the precondition. Log the property ID, seed, case index, and minimized input. Add a replay filter and promote minimized failures to named regression cases.

Start with four fixed seeds and 100 cases per seed per pure property on pull requests. Use smaller fixed raster fixtures and tune runtime to keep the required suite under five minutes. Run a larger rotating seed set nightly and record every seed used. Keep CI failures reproducible and require a passing regression for each confirmed counterexample. Compare decoded pixels and invariant regions instead of relying on encoded byte equality or font-dependent full-image snapshots.

## Delivery order

| Milestone | Work and dependencies | Exit evidence |
| --- | --- | --- |
| M0 — Foundation | Create a shared Xcode scheme, editor core test target, macOS CI job, and numbered capture/edit/export specs. Spike still capture and permission recovery on the provisional minimum OS. Add seed replay and demonstrate shrinking with a deliberately failing property. | Clean checkout builds and tests with `xcodebuild`. Record deployment target and capture API decisions. A replayed seed returns the same counterexample. |
| M1 — First complete workflow | Implement CAP-01 and the arrow and text subset of EDT-01. Add clipboard output from OUT-01. Wire the menu, one hotkey, basic accessibility, and fake capture integration. | Region → arrow → text → paste works on a real Mac and on simulated capture data. Geometry and initial export properties pass. |
| M2 — Capture and editor parity | Complete CAP-02/03, remaining EDT-01 tools, EDT-02/03, and visual pixelation. Add shortcut configuration, keyboard access, and draft discard behavior. | Full editing spec passes, including generated history and crop checks. Exercise permission recovery, capture cancellation, mixed displays, and source loss on real Macs. |
| M3 — Redaction and handoff | Finish EDT-04 and OUT-01/02. Add solid redaction, export formats, drag-out, share sheet, and cleanup. Test save failures and concurrent edits during export. | Redaction and export properties pass. Inspect flattened outputs from all handoff paths, including crop and overlapping annotation cases. |
| M4 — Beta and release | Finish UX-01. Validate signed builds, first-run permissions, accessibility, memory use, and large-image latency. Test with five people who regularly give visual feedback. | All required checks pass, with manual evidence on the minimum and a recent supported macOS version. At least four of five participants complete the core workflow unaided in under 30 seconds. Review any misses before release. |

Run pure and fake-backed integration checks on every PR. Run UI smoke checks for import → annotate → copy and cancel/retry with test fixtures. Reserve actual capture permissions, mixed-scale displays, VoiceOver, cross-app paste, and the signed build for the real-Mac release matrix. Before tagging, link each requirement to its evidence, resolve data-loss and export correctness defects, and record any accepted gaps in the release notes.
