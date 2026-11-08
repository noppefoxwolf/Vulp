# 0004. Load and cache image sequence frames individually

- Status: Accepted
- Date: 2026-11-08

## Context

Animated image playback needs a stable source download and independently cacheable decoded frames. Reissuing an ordinary image request on every animation tick would repeatedly replace view tasks and expose placeholder transitions. The core decoder also needs an explicit way to select a frame from a multi-frame source.

## Decision

- Add sequence capability through `ImageSequenceDeserializer` and `ImageSequenceLoading` protocols, keeping it generic and opt-in for loaders whose deserializer supports frame counting.
- Represent a loaded sequence as encoded data, a stable identifier, and a frame count. Each frame request selects its frame through `ImageDecodingOptions` and includes that index in its output cache identifier.
- Download the sequence source once. Create frame requests over the retained encoded data so the normal loader can decode, process, and cache each frame through its existing pipeline.
- Keep frame request creation, loading, and caching shared in `ImageSequence.loadFrames(using:targetSize:)`; platform UI targets own only playback scheduling.
- Keep one `ImageLoaderView` in the SwiftUI target. Its request initializer handles ordinary images; its sequence-asset initializer reads the loaded sequence's `frameCount`, shows a single frame as a still image, or predecodes and plays multiple frames on a timeline.
- In UIKit, support both `UIImageView` native frame animation and the package `ImageView` wrapper with a `UIDisplayLink` playback driver.
- Keep decoding and image processing on non-UI executors according to ADR 0003. Verify behavior with tests written before implementation according to ADR 0001.

## Consequences

- Consumers can also drive `ImageSequence.frameRequest(at:targetSize:)` themselves and control playback outside SwiftUI.
- Each requested frame is independently reusable through the normal image cache.
- SwiftUI and UIKit share the same decoded frame loading path while using platform-specific playback mechanisms.
- Playback prefetch and memory bounds are defined by [ADR 0006](0006-bounded-sequence-prefetch.md), which extends this decision with incremental frame loading.
- Frame selection is supported by decoders that opt into `ImageSequenceDeserializer`; ordinary `ImageDeserializer` implementations remain usable for static images.

> The UIKit playback driver in this record is superseded by [ADR 0014](0014-uiupdate-link-for-uikit-sequence-playback.md). The remaining decisions stay in effect.

## Alternatives considered

- Recreate a normal image view request for each tick: rejected because rapid request identity changes can cancel work and repeatedly show placeholders.
- Cache the whole animation as one platform image: rejected because callers cannot independently request or reuse decoded frame indexes.
- Add platform animation playback to the core target: rejected because playback belongs in UI integrations, while frame decoding and cache identity belong in the core target.
