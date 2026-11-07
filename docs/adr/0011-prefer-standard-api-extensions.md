# 0011. Prefer extensions on standard APIs for reusable implementations

- Status: Accepted
- Date: 2026-11-08

## Context

Standalone global functions can make reusable behavior harder to discover and can scatter related operations across the module. At the same time, attaching narrowly useful behavior to a broad standard type can make its API harder to understand.

## Decision

- Avoid adding standalone global functions when an existing type provides a natural home for the behavior.
- Do not move implementation helpers into `static` functions solely to avoid defining a global function. Keep specialized helpers as instance methods on the type that owns their behavior; keep computations that must run before initialization completes local to the initializer.
- Write reusable, general-purpose implementations as extensions on standard APIs such as Foundation types when appropriate.
- This preference does not apply when an implementation has limited applicability or would not be a natural responsibility of the extended type.

## Alternatives considered

- Put all helper implementations in global functions:
  - Benefits: behavior remains independent of existing types.
  - Costs: related operations become less discoverable and global names can accumulate.
- Put helpers in `static` functions on namespace-like types:
  - Benefits: avoids adding global names.
  - Costs: still separates behavior from the instance that owns it and only relocates the helper.
- Put every helper on a standard type extension:
  - Benefits: operations are discoverable from the type they use.
  - Costs: narrowly applicable helpers can clutter broad APIs and imply unsupported generality.

## Consequences

- Reusable behavior should be discoverable through the standard type it operates on when that is a natural fit.
- Narrowly scoped implementations should remain instance methods on the type or component that owns their use case.
- Type-level `static` APIs remain appropriate when the operation is inherently defined by the type, rather than being an implementation helper.
