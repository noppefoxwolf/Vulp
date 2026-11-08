# 0002. Separate platform UI integrations from the core target

- Status: Accepted
- Date: 2026-11-08

## Context

The core `Vulp` target contained both image-loading behavior and native view classes. This made consumers depend on UI implementation details even when they only needed the loading pipeline, and left AppKit without a dedicated module boundary.

## Decision

- Keep image loading, caching, downloading, deserialization, and processing in `Vulp`.
- Put SwiftUI, UIKit, and AppKit integrations in `Vulp_SwiftUI`, `Vulp_UIKit`, and `Vulp_AppKit` respectively.
- Keep `VulpUI` as an umbrella target that depends on and re-exports all three UI integrations.
- Keep each platform integration independently consumable.
- Use `MainActor` as the default isolation in UI integration targets. Keep the core loading target free of a `MainActor` default.

## Alternatives considered

- Keep native views in `Vulp`:
  - Benefits: fewer products and targets.
  - Costs: consumers inherit UI framework dependencies from the core module and platform APIs remain mixed together.

## Consequences

- UIKit and AppKit view APIs live in their matching targets; SwiftUI remains its own integration.
- UI module declarations are main-actor isolated by default, while the core package remains usable outside UI actor contexts.
- Platform-specific source files use conditional imports so the package's products remain buildable across supported platforms.
- Consumers can depend on only the UI integration they need, or use `VulpUI` for all UI integrations.
