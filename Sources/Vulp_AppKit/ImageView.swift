#if canImport(AppKit)
import AppKit
@_exported import Vulp

public enum ImageContentMode: String, Sendable {
    case scaleToFill
    case aspectFit
    case aspectFill
    case center
}

/// A container view that owns and lays out its image view.
@MainActor
public final class ImageView: NSView {
    private let imageView = NSImageView()
    private var storedImage: CGImage?

    public var image: CGImage? {
        get { storedImage }
        set {
            storedImage = newValue
            imageView.image = newValue.map {
                NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height))
            }
        }
    }

    public var contentMode: ImageContentMode = .aspectFit {
        didSet { updateContentMode() }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        updateContentMode()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(imageView)
        updateContentMode()
    }

    public override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    private func updateContentMode() {
        switch contentMode {
        case .scaleToFill: imageView.imageScaling = .scaleAxesIndependently
        case .aspectFit: imageView.imageScaling = .scaleProportionallyUpOrDown
        case .aspectFill: imageView.imageScaling = .scaleProportionallyDown
        case .center: imageView.imageScaling = .scaleNone
        }
    }
}
#endif
