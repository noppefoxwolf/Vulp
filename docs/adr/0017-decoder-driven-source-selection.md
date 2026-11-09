# 0017. Let decoders select supported media sources

- Status: Superseded by [0018](0018-runtime-sequence-decoder-selection.md)
- Date: 2026-11-09

## Context

The loader previously guessed a source's format from its URL extension and media hint before invoking the decoder. This made custom formats and extensionless URLs depend on loader-specific rules, even though each decoder has the best knowledge of the formats it can read.

## Decision

- Let each `MediaImageDecoding` report support for encoded data and direct URLs through `canDecode(data:)` and `canDecode(url:)`.
- Let `DefaultMediaImageLoader` accept an ordered decoder array and choose the first decoder that claims the source. Ask about a direct URL before downloading; if none claims it, load encoded data and route by its contents.
- Make `VideoFrameDecoding` refine `MediaImageDecoding` so video and custom URL decoders can live in the same array.
- Keep the typed sequence decoder as the loader's generic decoder value, and append it to the array as a fallback, so animated frame loading remains a static capability.
- Existing custom decoders retain their behavior through protocol defaults; custom decoders can opt into explicit source inspection.

## Alternatives considered

- Continue identifying sources through URL extensions and media hints:
  - Benefits: low-cost initial routing.
  - Costs: custom formats and extensionless URLs require changes to shared loader logic.
- Download every source before asking a decoder:
  - Benefits: one source representation for selection.
  - Costs: downloading a complete video just to generate a thumbnail.

## Consequences

- Custom decoders can own format recognition for their data or direct-URL sources.
- The standard AVFoundation decoder uses URL type metadata as a cheap precheck; ambiguous URLs are probed once during frame generation.
- Media type hints remain metadata for custom assets and decoders; the loader no longer relies on them for dispatch.
- Decoder support checks are additional async work and may perform source inspection before decoding.
