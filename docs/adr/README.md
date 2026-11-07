# Architecture Decision Records

This directory stores decisions that affect MediaLoader's architecture and public API.

## Adding a decision

1. Copy [`0000-template.md`](0000-template.md).
2. Give the file the next number in the `NNNN-short-title.md` format.
3. Fill in the context, decision, alternatives, and consequences. Use `Proposed` while the decision is under discussion and `Accepted` once settled.
4. Add a link to the record below.

## Records

- [0001. Swift concurrency, generic dispatch, and API design](0001-swift-concurrency-and-api-design.md)
- [0002. Separate platform UI integrations from the core target](0002-ui-target-boundaries.md)
- [0003. Run image work off UI actors](0003-run-image-work-off-ui-actors.md)
- [0004. Load and cache image sequence frames individually](0004-image-sequence-frame-loading.md)
- [0005. Do not require API compatibility before the first major release](0005-api-compatibility-before-major-release.md)
- [0006. Bound sequence frame prefetch during playback](0006-bounded-sequence-prefetch.md)
- [0007. Bucket processed image sizes by texture tiers](0007-bucket-image-output-sizes.md)
- [0008. Keep SwiftUI and UIKit image sizing behavior aligned](0008-swiftui-uikit-image-sizing-parity.md)
- [0009. Select sequence playback rates from source timing](0009-sequence-playback-frame-rate.md)
- [0010. Cache encoded image sources on disk](0010-cache-encoded-image-sources-on-disk.md)
- [0011. Prefer extensions on standard APIs for reusable implementations](0011-prefer-standard-api-extensions.md)
- [0012. Decode media sources through composed decoders](0012-media-source-decoding.md)
- [0013. Pass view scale into image requests](0013-pass-view-scale-into-image-requests.md)
