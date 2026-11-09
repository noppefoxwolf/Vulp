# 0016. Keep image presentation modes in UI targets

- Status: Accepted
- Date: 2026-11-09

## Context

The core image processor previously took a `.fit` or `.fill` presentation choice and encoded it into processed pixels and cache identity. The UI targets already expose platform-native content modes, so the same source and size could produce duplicate cached images based only on how a view displays them.

## Decision

- `ResizeImageProcessor` only downsamples the decoded image to fit within `MediaImageRequest.targetSize`, which is already bucketed from the requested size and display scale.
- Preserve the source aspect ratio and do not crop or upscale in the processing pipeline.
- Keep fit/fill behavior in UI targets: UIKit uses `UIImageView` content mode and SwiftUI uses image scaling modifiers.
- Remove presentation mode from request properties and cache identity.

## Alternatives considered

- Keep presentation modes in request processing:
  - Benefits: callers receive pixels already cropped for their chosen layout.
  - Costs: different views cannot share the same processed image cache entry.

## Consequences

- Different views using the same image and bucketed size can share one processed cache entry regardless of whether they display it with fit or fill.
- The UI can scale the processed image to its bounds; any resulting interpolation belongs to presentation behavior.
- This supersedes the `.fit` / `.fill` processing decision in [ADR 0015](0015-preserve-source-aspect-ratio-when-resizing.md); its source aspect-ratio requirement remains in effect.
