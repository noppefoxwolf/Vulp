#if canImport(UIKit)
import UIKit
import Vulp

extension AsyncImageView {
    /// Sets a placeholder independently of image loading. The same placeholder ID preserves existing work.
    /// The setting persists across sources until replaced, cleared with nil, or `image` is assigned.
    public func setPlaceholder(_ placeholder: ImagePlaceholder?) {
        placeholderLoading.setPlaceholder(placeholder) { [weak self] image in
            self?.displayPlaceholder(image)
        }
        if placeholder == nil { displayPlaceholder(nil) }
        startPlaceholderIfNeeded()
    }
}
#endif
