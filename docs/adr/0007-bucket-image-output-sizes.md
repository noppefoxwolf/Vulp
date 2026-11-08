# 0007. Bucket processed image sizes by texture tiers

- Status: Superseded by [ADR 0015](0015-preserve-source-aspect-ratio-when-resizing.md)
- Date: 2026-11-08

## Context

View dimensions often vary slightly while requesting the same source image. Exact-size processing creates many near-duplicate resized images and cache entries. SwiftUI also needs a way to derive pixel requests from the final laid-out view size and display scale.

## Decision

- Map built-in image request dimensions to a texture-friendly tier before processing and cache-key generation.
- Round the longest requested edge up to the next power of two and scale the other edge proportionally, preserving aspect ratio.
- Provide a SwiftUI view that reads its laid-out size and `displayScale`, then creates a request from those pixel dimensions.
- Reuse cached output when requests resolve to the same bucketed dimensions.

## Alternatives considered

- Cache every exact requested size:
  - Benefits: no extra pixels are produced.
  - Costs: small layout changes create duplicate processing work and cache entries.
- Round width and height independently to powers of two:
  - Benefits: both texture dimensions land on a power of two.
  - Costs: this changes image aspect ratio unless output is padded and adds unused texture area.

## Consequences

- Processed output can be larger than the exact view size, up to nearly twice its longest edge.
- Views in the same size tier share cached work when their aspect ratios produce the same output dimensions.
- The SwiftUI sized loader requires a request builder so callers can retain their own request capabilities and processing options.
