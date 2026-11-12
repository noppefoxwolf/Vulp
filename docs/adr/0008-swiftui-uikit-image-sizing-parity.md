# 0008. Keep SwiftUI and UIKit image sizing behavior aligned

- Status: Superseded in part by [ADR 0021](0021-add-swiftui-wrapper-for-uikit-view.md) and [ADR 0022](0022-keep-sizing-mode-types-in-ui-targets.md)
- Date: 2026-11-08

## Context

Vulp provides both SwiftUI and UIKit integrations. Routing SwiftUI through `UIViewRepresentable` could share some UIKit view behavior, but it would couple the SwiftUI integration to UIKit and require a separate AppKit path on macOS. The image size and cache behavior should remain consistent without forcing the view frameworks to share one wrapper implementation.

## Decision

- Keep SwiftUI and UIKit integrations native to their UI frameworks.
- Expose size behavior through `ImageViewSizingMode` on the existing image views instead of adding a separate view type for each sizing feature.
- Keep image sizing, bucket selection, processing, and cache-key behavior in the shared `Vulp` core.
- Size-aware SwiftUI integrations convert laid-out points to pixels with SwiftUI's `displayScale`; UIKit integrations use the view's display scale for the same conversion.
- Both integrations pass pixel dimensions through the same size bucketing and loading pipeline. Framework-specific adapters may differ in layout and rendering lifecycle, but must not change the resulting processing size or cache identity for equivalent view sizes and display scales.
- Sequence-loading APIs continue to accept an explicit pixel `targetSize`; their frame requests use the same core size bucketing and cache-key rules.
- Do not use `UIViewRepresentable` as the shared implementation strategy for SwiftUI.

## Alternatives considered

- Wrap the UIKit image view in `UIViewRepresentable`:
  - Benefits: shares UIKit-specific view and playback behavior on iOS.
  - Costs: couples SwiftUI to UIKit and needs a separate `NSViewRepresentable` implementation for macOS. It also mixes framework view lifecycle with shared image processing behavior.

## Consequences

- SwiftUI and UIKit can have different adapter code while preserving equivalent sizing, processing, and caching behavior.
- The existing view APIs select view-bound or explicit-pixel sizing through a property instead of introducing feature-specific view wrappers.
- Changes to bucketing or cache identity belong in the shared core and should be verified against both integrations.
- UIKit size-aware convenience APIs should use the view's actual bounds and display scale before creating image requests.
