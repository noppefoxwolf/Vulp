# 0019. Present UIKit images with CALayer

- Status: Accepted
- Date: 2026-11-09

## Context

The UIKit integration used a `UIImageView` subview to present images. Assigning an image to `UIImageView` participates in view layout, even though Vulp's decoders provide a decoded `CGImage` that is ready to display. The UIKit view also needs sizing behavior that depends on `ImageViewSizingMode`, including a corresponding intrinsic content size.

## Decision

- Present decoded images through a `CALayer` sublayer using the image's `CGImage` as layer contents.
- Set the contents scale from the `UIImage` scale and map UIKit `contentMode` values to `contentsGravity`.
- Keep image sizing in `AsyncImageView`: `.viewBounds` has no intrinsic content size, while `.explicitPixels` reports the displayed image's point size. Invalidate intrinsic content size when the image or sizing mode changes.
- Update the same layer for sequence playback frames.

## Alternatives considered

- Keep a `UIImageView` subview:
  - Benefits: UIKit manages image presentation and intrinsic sizing.
  - Costs: assigning images triggers view layout, and sizing behavior remains delegated to a child view rather than the sizing mode of `AsyncImageView`.

## Consequences

- The decoded `CGImage` is passed directly to Core Animation for display without introducing an image subview.
- `AsyncImageView` owns its intrinsic sizing and maps UIKit presentation modes to layer behavior.
- Changes to image content, sizing mode, and sequence frames must update the display layer and invalidate intrinsic size when appropriate.
