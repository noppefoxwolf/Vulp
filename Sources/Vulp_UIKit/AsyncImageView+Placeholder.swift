#if canImport(UIKit)
import UIKit

extension AsyncImageView {
    /// Replaces the placeholder provider without restarting the image request.
    /// A loaded image always takes precedence over a placeholder.
    public func setPlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?) {
        guard !hasLoadedImage || pendingPlaceholder != nil else {
            placeholderLoading.cancel()
            return
        }
        if pendingPlaceholder != nil {
            pendingPlaceholder = PendingImagePlaceholder(provider: placeholder, isConfigured: true)
        }
        configurePlaceholder(placeholder)
        if placeholder == nil, !hasLoadedImage { setDisplayedImage(nil) }
        resumePlaceholderIfNeeded()
    }

    /// A repeated request keeps its placeholder; a new source installs the pending provider.
    func resolvePlaceholderSource(changesSource: Bool) {
        if let pending = pendingPlaceholder {
            if changesSource {
                if !pending.isConfigured {
                    setDisplayedImage(nil)
                    configurePlaceholder(pending.provider)
                } else if hasLoadedImage {
                    setDisplayedImage(nil)
                }
            }
            pendingPlaceholder = nil
        } else if changesSource {
            placeholderLoading.cancel()
            setDisplayedImage(nil)
        }
    }

    /// Allows an initial placeholder to render before layout can identify the source.
    func configureUnresolvedPlaceholderIfNeeded() {
        guard var pending = pendingPlaceholder, !pending.isConfigured else { return }
        setDisplayedImage(nil)
        configurePlaceholder(pending.provider)
        pending.isConfigured = true
        pendingPlaceholder = pending
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

/// Stages a provider until the request builder identifies whether the source changed.
struct PendingImagePlaceholder {
    let provider: (@Sendable () async throws -> CGImage?)?
    var isConfigured = false
}
#endif
