import Foundation

/// A format hint supplied by a caller or inferred by the application.
public enum MediaTypeHint: Hashable, Sendable {
    case image
    case video
}
