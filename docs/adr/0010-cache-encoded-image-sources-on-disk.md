# 0010. Cache encoded image sources on disk

- Status: Accepted
- Date: 2026-11-08

## Context

The image cache stores decoded, processed images. Animated image playback also needs its encoded source to decode frames, but that source was only retained by the in-memory `ImageSequence`. Loading the source again after that value was released caused another download.

## Decision

- Add a separate `ImageDataCache` for encoded image data; do not mix source bytes into the decoded image cache.
- Use `DiskImageDataCache` by default in `DefaultMediaImageLoader`, keyed by `ImageAssetHandle.uniqueKey`, for both ordinary image loads and sequence loads.
- Bound the default disk cache to 100 MiB and seven days since last access. Allow callers to set a directory and limits, and to remove one or all entries.
- Treat cache read and write failures as misses or best-effort writes so they do not fail image loading.
- Keep HTTP freshness and invalidation responsibility outside this cache. Applications with mutable URLs should use versioned unique keys or explicitly remove cached data.

## Alternatives considered

- Store encoded source data in `ImageCache`:
  - Benefits: one cache API.
  - Costs: mixes raw data with platform image objects and prevents byte-based limits from being applied cleanly.
- Retain sequence data only in memory:
  - Benefits: no disk management or stale disk entries.
  - Costs: loading the same source again after the sequence is released can require another download.

## Consequences

- A later load can reuse encoded source bytes while decoded frames remain independently cached by frame index.
- Disk reads and writes are best effort; cache failures do not interrupt image loading.
- Mutable remote resources need a versioned cache key or explicit invalidation because the source cache does not interpret HTTP freshness headers.
