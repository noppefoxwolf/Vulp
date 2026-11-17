#if canImport(UIKit)
import UIKit

extension AsyncImageView {
    /// Sets a placeholder independently of image loading. A loaded image takes precedence.
    /// The setting persists across sources until replaced or `image` is assigned directly.
    public func setPlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?) {
        configurePlaceholder(placeholder, id: nil)
    }

    /// Keeps the existing provider when the ID is unchanged, including a nil ID.
    public func setPlaceholder(id: String?, _ placeholder: (@Sendable () async throws -> CGImage?)?) {
        guard placeholderIdentity != ImagePlaceholderIdentity(value: id) else { return }
        configurePlaceholder(placeholder, id: id)
    }

    private func configurePlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?, id: String?) {
        placeholderIdentity = ImagePlaceholderIdentity(value: id)
        placeholderLoading.setProvider(placeholder) { [weak self] image in
            self?.displayPlaceholder(image)
        }
        if placeholder == nil { displayPlaceholder(nil) }
        startPlaceholderIfNeeded()
    }
}

/// Distinguishes an unconfigured provider from a configured provider with a nil ID.
struct ImagePlaceholderIdentity: Equatable {
    let value: String?
}
#endif
