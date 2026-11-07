# 0003. Run image work off UI actors

- Status: Accepted
- Date: 2026-11-08

## Context

With `ApproachableConcurrency`, a nonisolated async function can continue on its caller's actor. Calling the image pipeline from a SwiftUI or UIKit view therefore does not by itself guarantee that synchronous decode and resize work leaves `MainActor`.

## Decision

- Keep `MainActor` as the default isolation for UI integration targets, but do not set it as the default for the core target.
- Mark image loading, deserialization, and processing async entry points `@concurrent` so they leave the caller's actor.
- Keep the public loading API async; callers await the result and update UI state on `MainActor` after the await.
- Use actors to isolate mutable state and serialize access. Do not pass an actor solely to schedule CPU work.

## Alternatives considered

- Pass a worker actor through the image pipeline:
  - Benefits: allows actor-isolated state to be used in the operation.
  - Costs: serializes work on that actor and couples the image API to a scheduling object.
- Leave nonisolated async functions to inherit caller isolation:
  - Benefits: simple call sites and fewer isolation hops.
  - Costs: synchronous ImageIO and Core Graphics work may execute on `MainActor`.

## Consequences

- Implementations of image loading, deserialization, and processing protocols must support calls that run concurrently with UI actors.
- Stateful implementations should isolate their mutable state in actors or another compiler-checked concurrency design.
- UIKit and SwiftUI state mutations remain on `MainActor` after asynchronous results return.
