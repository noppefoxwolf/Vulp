# 0026. Expose SwiftUI representable conformance

- Status: Accepted
- Date: 2026-11-17
- Supersedes in part: [ADR 0025](0025-hide-uikit-behind-swiftui-view.md)

## Context

Hiding `UIViewRepresentable` required a second view and forwarding every input. The intended API boundary concerns configuration types; representable conformance may remain public.

## Decision

- Make `AsyncImage` conform directly to `UIViewRepresentable`, exposing its required native view methods and coordinator type.
- Keep coordinator state private to the implementation.
- Retain SwiftUI `ContentMode` and the nested `AsyncImage.SizingMode`, converting them to UIKit configuration internally.
- Import `Vulp_UIKit` publicly for the representable method signatures without re-exporting its declarations.

## Alternatives considered

- Keep a private adapter:
  - Benefits: hides native view method signatures.
  - Costs: adds a redundant view and input forwarding.

## Consequences

- SwiftUI callers configure the view using SwiftUI-facing types.
- Native view access through representable requirements remains public.
- The additional adapter is removed without changing loading or layout behavior.
