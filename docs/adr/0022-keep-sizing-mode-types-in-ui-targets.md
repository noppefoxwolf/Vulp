# 0022. Keep sizing mode types in UI targets

- Status: Accepted
- Date: 2026-11-12
- Supersedes in part: [ADR 0008](0008-swiftui-uikit-image-sizing-parity.md)

## Context

`ImageViewSizingMode` describes how a UI view obtains its request size. It was declared in the `Vulp` core target only so the UIKit and SwiftUI targets could share one type, even though the core loading pipeline does not use it.

## Decision

- Keep UIKit's `ImageViewSizingMode` in the `Vulp_UIKit` target.
- Give `AsyncImageTimelineView` its own nested `SizingMode` with the same cases.
- Keep size bucketing, request construction, processing, and cache identity behavior in `Vulp`.
- Preserve equivalent sizing behavior between UI integrations without sharing a UI-only enum through the core target.

## Alternatives considered

- Keep one shared sizing mode in `Vulp`:
  - Benefits: UIKit and SwiftUI expose the same enum type.
  - Costs: the core target owns a type used only by UI integrations.
- Add a new common UI target for the shared enum:
  - Benefits: one shared enum remains outside the core target.
  - Costs: adds a target and dependency layer for a two-case value type.

## Consequences

- UIKit and SwiftUI APIs use distinct sizing mode types with matching cases.
- UI modules remain independently consumable, and the core remains free of view-sizing API types.
- Future sizing behavior changes must keep the two UI-facing enums aligned where their behavior is intended to match.
