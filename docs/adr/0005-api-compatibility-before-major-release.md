# 0005. Do not require API compatibility before the first major release

- Status: Accepted
- Date: 2026-11-08

## Context

Vulp's public API is still being shaped. Requiring backward compatibility before the first major release would constrain API improvements before the library's initial stable contract has been established.

## Decision

- Before the first major version is released, backward compatibility of public APIs is not required.
- Public APIs may be renamed, reshaped, or removed between pre-major releases when that improves the design. Update examples, tests, and documentation in the same change.
- This decision does not define the compatibility policy for major-version releases.

## Alternatives considered

- Preserve every public API from the first release: rejected because it would make early experimentation and API refinement unnecessarily costly.

## Consequences

- Consumers of pre-major releases may need to update their code when upgrading.
- Breaking public API changes should still be deliberate and reflected in the repository's examples, tests, and documentation.
- Compatibility expectations after the first major release need a separate policy.
