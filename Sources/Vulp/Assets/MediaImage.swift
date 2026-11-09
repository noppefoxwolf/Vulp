import CoreGraphics

/// A decoded bitmap shared by Vulp's loading pipeline and its UI integrations.
public typealias MediaImage = CGImage

public extension CGImage {
    var pixelWidth: Int { width }
    var pixelHeight: Int { height }
}
