# 0012. Decode media sources through composed decoders

- Status: Superseded by [0017](0017-decoder-driven-source-selection.md)
- Date: 2026-11-08

## Context

The loading pipeline accepted encoded image data only. Video thumbnails need a decoder that can read a URL directly, while animated image sequences still need encoded data and indexed frame decoding. Separate loaders would fragment the public API and duplicate caching and image processing.

## Decision

- Expose media-oriented names for the loading request, loader, and source abstractions. Keep compatibility type aliases for the existing pre-major API names.
- Keep one image-loading pipeline and compose an image/sequence decoder with a video frame decoder through `MediaImageDecoderSet`.
- Keep source identification in a resolver. Explicit media hints are best-effort; recognizable URL extensions can override conflicting hints. Ambiguous URLs are probed as video, then rechecked through the image-data path when no video source is recognized.
- Pass video URLs directly to AVFoundation. Do not download the full video into `Data` first. Generate the initial thumbnail at time zero.
- Keep sequence frame indexes and video timestamps as separate decoder concepts. Existing sequence playback and UI scheduling remain in UI targets.
- Keep decoder composition generic and statically checked; do not use runtime casts to discover decoder capabilities.

## Alternatives considered

- Add a separate video thumbnail loader and request family:
  - Benefits: isolated implementation.
  - Costs: splits the public loading interface and duplicates the image pipeline.
- Download all media into `Data` and dispatch decoders afterward:
  - Benefits: one input representation and one data cache.
  - Costs: can download an entire video to render one thumbnail.
- Dynamically register decoders and discover capabilities at runtime:
  - Benefits: open-ended plugin list.
  - Costs: less static capability checking and unnecessary runtime dispatch for the current decoder set.

## Consequences

- Remote video thumbnails use AVFoundation's URL loading path and do not share the image downloader's `URLSession` configuration.
- Automatic URL recognition relies on known extensions and an AVFoundation probe for ambiguous URLs; a failed video probe falls through to the regular image data path.
- The image output continues through the shared processor and image cache. Encoded image data remains in the existing data cache; complete video data is not cached there.
- The default video request selects time zero. A future time-selection API can be added separately from sequence frame indexes.
