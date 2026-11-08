# 0001. Swift concurrency, generic dispatch, and API design

- Status: Accepted
- Date: 2026-11-07

## Context

Vulp is a Swift image-loading library. Its implementation should make capability selection explicit, keep shared mutable state concurrency-safe, and remain straightforward to test and use from Swift.

## Decision

- Use generics and static constraints for request and processor capability selection. Do not use `as?` for application-level type dispatch.
- Do not use `NSLock` or `@unchecked Sendable`. Isolate mutable shared state with actors or another safe, compiler-checked concurrency design.
- Use test-driven development: add or update a test that describes behavior before implementing that behavior, then run the relevant tests.
- Prefer Swift-shaped APIs: clear argument labels, `async throws` for asynchronous work, explicit error types, generic constraints where they clarify supported operations, and value types where practical.

## Alternatives considered

- Runtime casts for optional capabilities: rejected because unsupported combinations are discovered at runtime and make invalid states easier to represent.
- Locks or unchecked sendability for shared state: rejected because they shift synchronization guarantees from the compiler to manual discipline.
- Implement first and add tests afterward: rejected because it does not establish expected behavior before implementation.

## Consequences

- Loaders and request types may become generic so a request's capabilities and processor support are checked at compile time.
- In-flight request coordination and caches use actor isolation; callers can cancel their own async wait without canceling shared work needed by other callers.
- Foundation APIs may expose a broad response type even when the concrete transport is HTTP. Any required platform-boundary conversion must stay isolated in the transport adapter and must not be used for application-level dispatch.
- New behavior should be introduced with focused tests before the implementation changes.
