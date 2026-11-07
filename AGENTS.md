# Repository guidance

## Architecture Decision Records

- Save Architecture Decision Records (ADRs) in `docs/adr/`.
- Name each record `NNNN-short-title.md`, using the next available four-digit number (for example, `0001-image-loading-api.md`).
- Start new records from `docs/adr/0000-template.md` and update the index in `docs/adr/README.md` when adding an ADR.
- Keep accepted decisions as historical records. If a decision changes, add a new ADR and mark the earlier record as superseded.
- Follow accepted ADRs while implementing code. In particular, follow [ADR 0001](docs/adr/0001-swift-concurrency-and-api-design.md) for generics, TDD, and Swift API design, [ADR 0002](docs/adr/0002-ui-target-boundaries.md) for package target boundaries, and [ADR 0003](docs/adr/0003-run-image-work-off-ui-actors.md) for actor isolation and image processing execution.
- Before the first major release, public API backward compatibility is not required; deliberate API changes are allowed. Follow [ADR 0005](docs/adr/0005-api-compatibility-before-major-release.md), which leaves the post-major compatibility policy open for a separate decision.
- For animated image sequences, follow [ADR 0004](docs/adr/0004-image-sequence-frame-loading.md): download the encoded source once, select frames through decoding options, key the decoded image cache by frame index, and keep playback in the shared image view in UI targets. Write behavior tests before implementation and consider the memory cost of preloading every frame.
