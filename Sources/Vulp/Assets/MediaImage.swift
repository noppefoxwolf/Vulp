#if canImport(UIKit)
import UIKit

/// Platform image type used by Vulp.
public typealias MediaImage = UIImage

public extension UIImage {
    var pixelWidth: Int { cgImage?.width ?? 0 }
    var pixelHeight: Int { cgImage?.height ?? 0 }
    var isTemplateImage: Bool { renderingMode == .alwaysTemplate }
}
#elseif canImport(AppKit)
import AppKit

/// Platform image type used by Vulp.
public typealias MediaImage = NSImage

public extension NSImage {
    var isTemplateImage: Bool { isTemplate }

    var pixelWidth: Int {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)?.width ?? 0
    }

    var pixelHeight: Int {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)?.height ?? 0
    }
}
#endif
