# 0027. Use a delegate for UIKit image load completion

- Status: Accepted
- Date: 2026-11-17

## Context

UIKit consumers need delegate-based completion, while the SwiftUI wrapper needs to bridge those events through its Coordinator.

## Decision

- Replace UIKit load completion closures with a main-actor, class-bound `AsyncImageViewDelegate` and a weak `delegate` property.
- Report the existing completion result after displaying a still image or the first sequence frame, and report non-cancellation load failures.
- Keep explicit async loads caller-owned, without delegate notifications.
- Make the SwiftUI Coordinator implement the delegate and forward events to the latest SwiftUI `onCompletion` closure on every update, including unchanged URLs.

## Alternatives considered

- Retain completion closures in UIKit:
  - Benefits: convenient per-call handlers.
  - Costs: does not provide the requested UIKit delegate convention.

## Consequences

- UIKit clients retain and assign their delegate before starting loads.
- SwiftUI clients retain their existing completion API.
- Request-builder closures remain part of request construction.
