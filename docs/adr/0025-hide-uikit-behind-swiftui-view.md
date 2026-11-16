# 0025. Hide UIKit implementation behind the SwiftUI view

- Status: Accepted
- Date: 2026-11-17
- Supersedes in part: [ADR 0021](0021-add-swiftui-wrapper-for-uikit-view.md)

## Context

The UIKit-backed SwiftUI `AsyncImage` publicly conformed to `UIViewRepresentable`, exposing the native view, coordinator, UIKit content mode, and UIKit sizing type to SwiftUI clients.

## Decision

- Expose `AsyncImage` as a SwiftUI `View` with an opaque body and keep its `UIViewRepresentable` adapter and coordinator private.
- Accept SwiftUI `ContentMode` (`fit` or `fill`) and a nested `AsyncImage.SizingMode` with `viewBounds` and `explicitPixels` cases.
- Translate configuration into UIKit types inside the private adapter and stop re-exporting `Vulp_UIKit` from the wrapper module.
- Preserve UIKit loading, layout, completion, and sequence playback behavior.

## Alternatives considered

- Keep the public representable and UIKit configuration types:
  - Benefits: direct access to all UIKit content modes.
  - Costs: UIKit implementation details become part of the SwiftUI API contract.

## Consequences

- SwiftUI consumers can configure the view without naming UIKit types.
- Existing callers must replace UIKit content modes with `fit` or `fill` and use the nested sizing type.
- UIKit remains independently available through `Vulp_UIKit` and the `VulpUI` umbrella.
