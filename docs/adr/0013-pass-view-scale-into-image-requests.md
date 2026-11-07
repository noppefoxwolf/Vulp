# 0013. Pass view scale into image requests

- Status: Accepted
- Date: 2026-11-08

## Context

Size-aware UI integrations know a laid-out size in points and a display scale. Requiring each view adapter to multiply those values duplicates pixel conversion at the UI boundary and makes request builders receive framework-derived pixel dimensions.

## Decision

- Size-aware SwiftUI and UIKit request builders receive a point size and display scale.
- `MediaImageRequest` multiplies those values, buckets the resulting pixel dimensions, and uses the bucketed pixels for processing and cache identity.
- A scale of `1` preserves explicit pixel-size request behavior, including sequence frame requests.
- Invalid or overflowing scales and dimensions are rejected as invalid target sizes.

## Alternatives considered

- Keep point-to-pixel conversion in each UI adapter:
  - Benefits: the core request continues to receive pixels only.
  - Costs: the conversion is duplicated and request builders must interpret framework-provided dimensions as pixels.

## Consequences

- Request-builder closures receive both a point size and a scale.
- Scale affects cache identity through the resulting bucketed pixel dimensions; equivalent pixel outputs can share cached work.
- Existing explicit pixel-size callers keep scale at its default of `1`.
