#if canImport(UIKit)
import UIKit

extension AsyncImageView {
    /// Replaces the placeholder provider without restarting the image request.
    /// A loaded image always takes precedence over a placeholder.
    public func setPlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?) {
        guard !hasLoadedImage || hasPendingSourceSelection else {
            placeholderLoading.cancel()
            return
        }
        configurePlaceholder(placeholder)
        if placeholder == nil, !hasLoadedImage { setDisplayedImage(nil) }
        resumePlaceholderIfNeeded()
    }

    func configurePlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?) {
        placeholderLoading.configure(placeholder) { [weak self] image in
            guard let self, !self.hasLoadedImage else { return }
            self.setDisplayedImage(image)
        }
    }

    func resumePlaceholderIfNeeded() {
        guard !hasLoadedImage, !isImageLoadDetached else { return }
        placeholderLoading.resume()
    }

    func setInitialPlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?) {
        setDisplayedImage(nil)
        setPlaceholder(placeholder)
    }
}
#endif
