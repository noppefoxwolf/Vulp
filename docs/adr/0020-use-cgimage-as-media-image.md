# 0020. Use CGImage as the decoded MediaImage type

- Status: Accepted
- Date: 2026-11-09

## Context

Vulp's decoders already produce decoded `CGImage` values, but immediately wrapped them in `UIImage` or `NSImage`. The processor then extracted the `CGImage` again to resize pixels. These platform wrappers carry UI presentation details such as scale and template rendering mode, while the shared loading and caching pipeline handles decoded pixel data.

The UIKit integration now presents a `CGImage` directly through Core Animation. Keeping `MediaImage` platform-specific would continue wrapping and unwrapping the same bitmap as images flow through decoders, processors, caches, sequences, and UI targets.

## Decision

- Define `MediaImage` as `CGImage` for the shared loading, decoding, processing, and caching pipeline.
- Have decoders and processors return `CGImage` directly. Treat the decoded pixel dimensions as the image dimensions; platform image scale and orientation wrappers are not part of `MediaImage`.
- Keep rendering mode as request metadata and apply it in UI targets. Do not bake template/original presentation state into the decoded bitmap or its cache identity.
- Create `UIImage` and `NSImage` wrappers only at UI boundaries that require them. UIKit's layer-backed view accepts and displays `CGImage` directly.
- Keep intrinsic sizing in the UI integration: explicit pixel images report pixel dimensions as points; bounds-sized views derive their size from layout.

## Alternatives considered

- Keep `MediaImage` as `UIImage` on UIKit and `NSImage` on AppKit:
  - Benefits: UI targets receive native image objects with scale and rendering metadata already attached.
  - Costs: the core pipeline must wrap decoded bitmaps for processing and unwrap them again, and UI-specific types remain part of shared loading and caching APIs.

- Add a custom image wrapper containing a `CGImage` and presentation metadata:
  - Benefits: scale and rendering hints travel alongside the bitmap.
  - Costs: adds a wrapper when request metadata and UI boundaries already provide those semantics.

## Consequences

- `MediaImage`, fallback image parameters, processor inputs/outputs, and UIKit image properties now use `CGImage`; this is a deliberate public API change before the first major release.
- The same decoded bitmap can be cached and reused for original and template presentation modes.
- SwiftUI applies `Image.RenderingMode` when creating its `Image`; UIKit applies template tinting in its display layer; AppKit creates an `NSImage` only when assigning to `NSImageView`.
- Callers that need a platform image must create it at their UI boundary and provide any presentation metadata separately.
