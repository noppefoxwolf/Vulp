#if canImport(UIKit)
import UIKit

extension AsyncImageView {
    /// Replaces the placeholder provider without restarting the image request.
    /// A loaded image always takes precedence over a placeholder.
    public func setPlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?) {
        replacePlaceholder(placeholder, id: nil)
    }

    /// Updates the provider only when its identity changes. The initial nil ID is a valid identity.
    public func setPlaceholder(id: String?, _ placeholder: (@Sendable () async throws -> CGImage?)?) {
        if let pending = pendingPlaceholder {
            guard pending.id != id else { return }
        } else {
            guard placeholderIdentity != ImagePlaceholderIdentity(value: id) else { return }
        }
        replacePlaceholder(placeholder, id: id)
    }

    private func replacePlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?, id: String?) {
        guard !hasLoadedImage || pendingPlaceholder != nil else {
            placeholderIdentity = ImagePlaceholderIdentity(value: id)
            placeholderLoading.cancel()
            return
        }
        if pendingPlaceholder != nil {
            pendingPlaceholder = PendingImagePlaceholder(provider: placeholder, id: id, isConfigured: true)
        }
        configurePlaceholder(placeholder, id: id)
        if placeholder == nil, !hasLoadedImage { setDisplayedImage(nil) }
        resumePlaceholderIfNeeded()
    }

    /// A repeated request keeps its placeholder; a new source installs the pending provider.
    func resolvePlaceholderSource(changesSource: Bool) {
        if let pending = pendingPlaceholder {
            if changesSource {
                if !pending.isConfigured {
                    setDisplayedImage(nil)
                    configurePlaceholder(pending.provider, id: pending.id)
                } else if hasLoadedImage {
                    setDisplayedImage(nil)
                }
            } else if placeholderIdentity != ImagePlaceholderIdentity(value: pending.id) {
                configurePlaceholder(pending.provider, id: pending.id)
                if pending.provider == nil, !hasLoadedImage { setDisplayedImage(nil) }
            }
            pendingPlaceholder = nil
        } else if changesSource {
            placeholderIdentity = nil
            placeholderLoading.cancel()
            setDisplayedImage(nil)
        }
    }

    /// Allows an initial placeholder to render before layout can identify the source.
    func configureUnresolvedPlaceholderIfNeeded() {
        guard var pending = pendingPlaceholder, !pending.isConfigured else { return }
        setDisplayedImage(nil)
        configurePlaceholder(pending.provider, id: pending.id)
        pending.isConfigured = true
        pendingPlaceholder = pending
    }

    func configurePlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?, id: String?) {
        placeholderIdentity = ImagePlaceholderIdentity(value: id)
        placeholderLoading.configure(placeholder) { [weak self] image in
            guard let self, !self.hasLoadedImage else { return }
            self.setDisplayedImage(image)
        }
    }

    func resumePlaceholderIfNeeded() {
        guard !hasLoadedImage, !isImageLoadDetached else { return }
        placeholderLoading.resume()
    }

    func setInitialPlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?, id: String?) {
        setDisplayedImage(nil)
        replacePlaceholder(placeholder, id: id)
    }
}

/// Stages a provider until the request builder identifies whether the source changed.
struct PendingImagePlaceholder {
    let provider: (@Sendable () async throws -> CGImage?)?
    let id: String?
    var isConfigured = false
}
/// Distinguishes an unconfigured provider from a configured provider with a nil ID.
struct ImagePlaceholderIdentity: Equatable {
    let value: String?
}
#endif
