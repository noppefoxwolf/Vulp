# 0006. Bound sequence frame prefetch during playback

- Status: Accepted
- Date: 2026-11-08

## Context

The sequence playback integrations loaded and retained every decoded frame before displaying the first frame. Long animations could therefore delay first display and use memory proportional to the full sequence length.

## Decision

- Keep downloading the encoded sequence source once and keep decoded frames independently cacheable by frame index, as decided in ADR 0004.
- Add a shared `ImageSequenceFrameLoader` that loads the requested frame and a configurable number of following frames. Its retained frame task window is bounded and wraps at the end of the sequence.
- Show the first frame as soon as it loads, then let the UI targets schedule playback and request frames incrementally.
- Default playback lookahead to three frames. Callers using the frame loader directly may choose a different count, including zero.

## Alternatives considered

- Decode all frames before playback: rejected because first display is delayed and decoded-image memory grows with the full sequence.
- Move playback scheduling into the core target: rejected because UIKit and SwiftUI own different playback lifecycles.

## Consequences

- Playback starts after the first decoded frame, while nearby frames load ahead through the regular cache pipeline.
- UI playback retains only the active frame and the bounded lookahead window instead of an array containing the whole animation.
- If decoding falls behind playback, a frame can still take longer than the requested frame duration to load.
