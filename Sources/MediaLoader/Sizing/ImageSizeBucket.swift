import Foundation

/// Maps requested pixel dimensions to a texture-friendly size tier.
public enum ImageSizeBucket {
    /// Rounds the longest edge up to a power-of-two tier while preserving the image aspect ratio.
    /// Returns `nil` when the requested dimensions cannot be represented safely as pixel counts.
    public static func pixelSize(for requestedSize: CGSize) -> CGSize? {
        guard requestedSize.width.isFinite,
              requestedSize.height.isFinite,
              requestedSize.width >= 0,
              requestedSize.height >= 0
        else {
            return nil
        }

        guard requestedSize.width > 0, requestedSize.height > 0 else {
            return .zero
        }

        let longestEdge = max(requestedSize.width, requestedSize.height)
        let maximumRepresentableDimension = CGFloat(Int.max / 2)
        guard longestEdge <= maximumRepresentableDimension else { return nil }

        var tier: CGFloat = 1
        while tier < longestEdge {
            tier *= 2
        }

        let scale = tier / longestEdge
        let width = max(1, Int((requestedSize.width * scale).rounded()))
        let height = max(1, Int((requestedSize.height * scale).rounded()))
        return CGSize(width: width, height: height)
    }
}
