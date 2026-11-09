# 0018. Select sequence decoders from the runtime decoder list

- Status: Accepted
- Date: 2026-11-09

## Context

Requiring a concrete generic sequence decoder made the loader's decoder array incomplete: one decoder had to be singled out by type even though all other decoding capabilities were selected at runtime. Animated-image sequence support should be discoverable from the same ordered decoder list.

## Decision

- Put sequence capability checks and sequence metadata operations on `MediaImageDecoding`.
- Require every decoder to implement the data and URL support checks so ordered routing cannot silently select a catch-all default.
- Let `canDecodeSequence(data:)` default to `false`; non-sequence decoders provide unsupported defaults for frame count and frame duration operations.
- Select the first decoder that reports sequence support when loading a sequence.
- Remove the sequence decoder generic parameter and accept only the ordered decoder array in `DefaultMediaImageLoader`.
- Keep `MediaImageSequenceDecoding` as a convenience refinement for decoders that implement sequence support.

## Alternatives considered

- Keep a separately typed sequence decoder:
  - Benefits: compile-time sequence capability checking.
  - Costs: callers must provide a special decoder outside the decoder array.
- Discover sequence support through a runtime cast:
  - Benefits: no additional protocol requirements.
  - Costs: capability selection depends on unchecked type inspection.

## Consequences

- Default loaders expose sequence loading, and report unsupported media at runtime when no registered decoder supports sequences.
- Custom decoders can opt into sequence loading by implementing the capability check and metadata operations.
- The decoder registry has one configuration path for image data, direct URLs, and animated sequences.
