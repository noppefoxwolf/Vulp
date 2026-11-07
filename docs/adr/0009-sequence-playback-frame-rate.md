# 0009. Select sequence playback rates from source timing

- Status: Accepted
- Date: 2026-11-08

## Context

Sequence playback needs to fit encoded frame delays to display refresh intervals and optionally skip source frames to reduce update work. UIKit and SwiftUI should share the same policy.

## Decision

- Read each frame's display duration while inspecting a sequence. Deserializers without timing metadata use a 0.1 second fallback per frame.
- Expose `ImageSequencePlaybackPlan` in the core target. It chooses a supported display rate and maps display ticks to source frame indexes.
- Callers configure `levelOfIntegrity` from 0 through 1. Lower values allow more source frames to be skipped. Values outside the range are clamped.
- UI sequence playback APIs accept `levelOfIntegrity`, defaulting to 1. Playback scheduling remains owned by UI targets as defined in ADR 0004.

## Alternatives considered

- Ask callers to choose a fixed frame rate: rejected because encoded sources carry individual frame durations that should drive playback.
- Put playback scheduling in the core target: rejected because playback remains platform UI behavior.

## Consequences

- UIKit and SwiftUI share a plan computed from source timing and integrity preference.
- Lower integrity reduces the number of displayed source frames.
- Decoders without per-frame timing metadata use a uniform fallback duration.
