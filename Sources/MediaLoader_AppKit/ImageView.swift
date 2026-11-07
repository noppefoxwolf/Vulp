#if canImport(AppKit)
import AppKit
@_exported import MediaLoader

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

    public var image: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
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
