#if canImport(UIKit)
import UIKit

/// Receives results from view-managed image loads on the main actor.
@MainActor
public protocol AsyncImageViewDelegate: AnyObject {
    /// Called after displaying a still image or the first sequence frame, or when loading fails.
    /// Cancellation and caller-owned `async throws` loads do not send this notification.
    func asyncImageView(_ imageView: AsyncImageView, didComplete result: Result<CGImage, any Error>)
}
#endif
