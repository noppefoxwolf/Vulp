#if canImport(UIKit)
import UIKit

/// Receives lifecycle events from view-managed image loads on the main actor.
@MainActor
public protocol AsyncImageViewDelegate: AnyObject {
    /// Called before a view-managed load begins, including loads triggered by resizing or reattachment.
    /// Reused in-flight or displayed images and caller-owned `async throws` loads do not send this notification.
    func asyncImageViewDidStartLoading(_ imageView: AsyncImageView)

    /// Called after displaying a still image or the first sequence frame, or when loading fails.
    /// Cancellation and caller-owned `async throws` loads do not send this notification.
    func asyncImageView(_ imageView: AsyncImageView, didComplete result: Result<CGImage, any Error>)
}

public extension AsyncImageViewDelegate {
    func asyncImageViewDidStartLoading(_ imageView: AsyncImageView) {}
}
#endif
