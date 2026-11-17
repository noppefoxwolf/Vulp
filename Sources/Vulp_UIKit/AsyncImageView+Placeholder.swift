#if canImport(UIKit)
import UIKit
import Vulp

extension AsyncImageView {
    /// Sets a placeholder independently of image loading. The same asset ID preserves existing work.
    /// The setting persists across sources until replaced, cleared with nil, or `image` is assigned.
    public func setPlaceholder(_ asset: PlaceholderAsset?) {
        placeholderLoading.setAsset(asset) { [weak self] image in
            self?.displayPlaceholder(image)
        }
        if asset == nil { displayPlaceholder(nil) }
        startPlaceholderIfNeeded()
    }
}
#endif
