# 0024. Select sequence playback from loaded media data

- Status: Accepted
- Date: 2026-11-12

## Context

Image views need to play animated sources automatically, including requests created through the ordinary image-loading API. Runtime casts from a general loader to a sequence-loading protocol make playback depend on the loader's declared type instead of asking the loader to inspect the actual asset.

## Decision

- Add `loadSequence(from:)` to `MediaImageLoading` with a default implementation that throws `ImageSequenceError.unsupportedMediaSource`.
- Have UIKit request-driven loading try sequence inspection and fall back to ordinary image loading when the source is unsupported or has no animated playback plan.
- Keep `MediaImageSequenceLoading` as a refinement for APIs that explicitly require sequence support; automatic request loading does not runtime-cast to it.

## Alternatives considered

- Runtime-cast a general loader to `MediaImageSequenceLoading`:
  - Benefits: keeps sequence methods off the base loading protocol.
  - Costs: automatic playback depends on runtime protocol conformance rather than source data.

## Consequences

- Ordinary loaders need no changes because the base protocol supplies the unsupported default.
- Custom loaders can opt into data-driven playback by implementing `loadSequence(from:)`.
- UIKit request-based loading can select still-image or sequence playback from the loaded asset.
