# 0023. Select decoders from local source files

- Status: Accepted
- Date: 2026-11-12
- Supersedes: Direct-URL source selection in [0018](0018-runtime-sequence-decoder-selection.md)

## Context

Selecting a decoder from the original remote URL can trust a misleading or missing extension and bypass the encoded source cache. Video decoding also needs a file URL, while the loader's data cache previously exposed only bytes.

## Decision

- Load source data from the asset or encoded-source cache before selecting a decoder.
- Use a cached local file URL for URL-based inspection when the cache provides one; otherwise stage the bytes into a temporary local file.
- Select every decoder through `canDecode(url:)` using a local source file URL; keep encoded `Data` for decoding and sequence capability checks.
- Have the built-in video decoder inspect the local asset's tracks instead of inferring media type from the filename extension.
- Use `Asset` names for source files, source bytes, and their caches; use `Image` names for decoded and processed image values.
- Use `decode` consistently for converting encoded image data or video frames into `MediaImage` values.
- Keep video frame decoding on `MediaImageDecoding`; do not split it into a separate decoder protocol.

## Alternatives considered

- Probe the original remote URL before downloading:
  - Benefits: can avoid fetching a full video for thumbnail generation.
  - Costs: classification depends on remote URL metadata and does not use the cached file.
- Select solely from encoded data:
  - Benefits: no local-file inspection API.
  - Costs: some media frameworks need a file URL for reliable inspection and frame extraction.

## Consequences

- Direct-URL video loading now downloads the source before generating its thumbnail.
- Asset data caches expose their local source URL; caches without file storage use a temporary file for URL-based inspection.
- Sequence decoder selection remains as defined in ADR 0018, but known video sources are identified from their local cached file.
