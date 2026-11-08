# 0014. Use UIUpdateLink for UIKit sequence playback

- Status: Accepted
- Date: 2026-11-09

## Context

UIKit sequence playback needs to schedule frame changes in sync with UI updates. `CADisplayLink` provides display synchronization, but UIKit now provides `UIUpdateLink`, which integrates with the view update lifecycle and follows the display associated with its view.

## Decision

- Set the package minimum iOS version to iOS 18.
- Drive UIKit image sequence playback with a `UIUpdateLink` associated with the image view.
- Request continuous updates during playback and use `UIUpdateInfo.modelTime` to select the frame due at the current playback time.
- Keep frame loading asynchronous and bounded; when loading falls behind, show the latest due frame rather than replaying stale frames.

## Alternatives considered

- Keep `CADisplayLink`: rejected because `UIUpdateLink` participates in UIKit's update lifecycle and automatically tracks the view's display.
- Keep `Task.sleep`: rejected because timer wakeups are not synchronized with UI updates.

## Consequences

- UIKit playback timing follows UI updates and adapts when the view moves between displays.
- The package no longer supports iOS versions earlier than 18.
- SwiftUI playback remains owned by its existing SwiftUI integration.
