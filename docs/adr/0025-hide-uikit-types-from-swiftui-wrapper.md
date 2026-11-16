# 0025. Hide UIKit types from the SwiftUI wrapper API

- Status: Accepted
- Date: 2026-11-16
- Supersedes in part: [ADR 0021](0021-add-swiftui-wrapper-for-uikit-view.md)

## Context

The opt-in SwiftUI wrapper exposed UIKit-specific configuration types and the concrete UIKit image view in its public API. Clients using the SwiftUI wrapper should be able to configure it with SwiftUI types and should not need to know Vulp's UIKit view class.

## Decision

- Keep the UIKit-backed SwiftUI integration and its existing image loading and playback behavior.
- Keep the public wrapper as a `UIViewRepresentable`, using `UIView` as its representable type so the concrete Vulp UIKit view class stays out of its signatures.
- Use SwiftUI's `ContentMode` and a SwiftUI-target-owned sizing mode in the public configuration, translating them to UIKit types inside the wrapper.
- Do not re-export `Vulp_UIKit` from the SwiftUI wrapper module.

## Alternatives considered

- Keep UIKit types in the public API:
  - Benefits: no translation layer and direct access to UIKit configuration.
  - Costs: SwiftUI clients must understand UIKit types and the wrapper leaks implementation details.

## Consequences

- SwiftUI clients configure the wrapper with SwiftUI types; protocol witnesses use the base `UIView` type required by `UIViewRepresentable`.
- The concrete Vulp UIKit image view and UIKit-specific configuration types remain implementation details.
- The wrapper remains available only on platforms that support both SwiftUI and UIKit.
- Future wrapper configuration must map from SwiftUI-target-owned types to the UIKit implementation.
