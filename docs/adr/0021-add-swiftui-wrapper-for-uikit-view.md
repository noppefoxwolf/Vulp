# 0021. Add a SwiftUI wrapper for the UIKit image view

- Status: Accepted
- Date: 2026-11-10

## Context

The native SwiftUI integration and UIKit integration have separate view implementations, as decided in [ADR 0008](0008-swiftui-uikit-image-sizing-parity.md). Some SwiftUI clients also need the UIKit view's layer-backed presentation and display-synchronized sequence playback.

## Decision

- Keep `Vulp_SwiftUI` as the native SwiftUI integration and preserve its independent loading, sizing, and playback implementation.
- Add `Vulp_SwiftUI_Vulp_UIKit` as an opt-in SwiftUI integration that depends on `Vulp_UIKit` and wraps `AsyncImageView` with `UIViewRepresentable`.
- Expose the wrapper as `UIKitAsyncImage`, with URL loading, content mode, sizing mode, sequence playback settings, and failure handling.
- Keep request sizing and image processing semantics in the existing UIKit view and shared core. The wrapper forwards layout and configuration to the UIKit view rather than implementing another loading pipeline.
- Make the wrapper available through its own library product and the `VulpUI` umbrella target.

## Alternatives considered

- Replace the native SwiftUI view with a UIKit wrapper:
  - Benefits: a single view implementation on iOS.
  - Costs: SwiftUI would depend on UIKit behavior and lose its native lifecycle, while macOS would need a separate AppKit path.
- Keep only the native SwiftUI integration:
  - Benefits: no additional target or API.
  - Costs: SwiftUI clients cannot opt into UIKit's layer-backed view and playback behavior.

## Consequences

- SwiftUI clients can select the UIKit-backed view by importing `Vulp_SwiftUI_Vulp_UIKit`, or use it through `VulpUI`.
- The existing native SwiftUI API remains available and continues to follow ADR 0008's sizing parity requirements.
- The wrapper is available only where both SwiftUI and UIKit can be imported.
