#if canImport(UIKit)
import UIKit
@_exported import Vulp

/// A layer-backed image view that sizes image requests from its bounds when requested.
@MainActor
public final class AsyncImageView: UIView {
    private let imageLayer = CALayer()
    private let sequencePlayback = ImageSequencePlayback()
    private var displayedImage: CGImage?
    private var makeImageOperation: (@MainActor @Sendable (CGSize?, CGFloat) -> ImageLoadingOperation?)?
    private var restartImageLoadOnAttach: (@MainActor @Sendable () -> Void)?
    private var currentCacheIdentifier: String?
    private var loadedCacheIdentifier: String?
    private var loadedStaticSequenceIdentifier: String?
    private var imageLoadTask: Task<Void, Never>?
    private var imageFailureHandler: (@MainActor @Sendable (any Error) -> Void)?

    /// Controls request-builder loads and intrinsic sizing; sequence loads use their explicit `targetSize` argument.
    public var sizingMode: ImageViewSizingMode = .viewBounds {
        didSet {
            guard sizingMode != oldValue else { return }
            currentCacheIdentifier = nil
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            updateImageIfNeeded()
        }
    }

    public var image: CGImage? {
        get { displayedImage }
        set {
            imageLoadTask?.cancel()
            imageLoadTask = nil
            makeImageOperation = nil
            restartImageLoadOnAttach = nil
            currentCacheIdentifier = nil
            loadedCacheIdentifier = nil
            loadedStaticSequenceIdentifier = nil
            sequencePlayback.stop()
            setDisplayedImage(newValue)
        }
    }

    public override var contentMode: UIView.ContentMode {
        didSet {
            guard contentMode != oldValue else { return }
            setNeedsLayout()
        }
    }

    public override var intrinsicContentSize: CGSize {
        // Bound-sized images are measured by Auto Layout; explicit images contribute pixel dimensions as points.
        guard sizingMode == .explicitPixels, let image else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        return CGSize(width: image.width, height: image.height)
    }

    /// Loads and plays an image source from a URL at this view's current pixel size.
    public func loadImage(
        url: URL,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil
    ) {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        makeImageOperation = nil
        currentCacheIdentifier = nil
        loadedCacheIdentifier = nil
        loadedStaticSequenceIdentifier = nil
        let asset = RemoteMediaAsset(url: url)
        restartImageLoadOnAttach = { [weak self] in
            self?.startImageLoad(
                asset: asset,
                levelOfIntegrity: levelOfIntegrity,
                prefetchCount: prefetchCount,
                onFailure: onFailure
            )
        }
        sequencePlayback.stop()
        imageFailureHandler = onFailure
        setDisplayedImage(nil)
        if window != nil {
            startImageLoad(
                asset: asset,
                levelOfIntegrity: levelOfIntegrity,
                prefetchCount: prefetchCount,
                onFailure: onFailure
            )
        }
    }

    /// Loads an image source and plays it when it contains multiple frames.
    public func loadImage(
        asset: any MediaAsset,
        targetSize: CGSize,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3
    ) async throws {
        try await loadImage(
            asset: asset,
            using: MediaImageLoader.default,
            targetSize: targetSize,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount
        )
    }

    /// Loads an image source and plays it when it contains multiple frames.
    public func loadImage<Loader: MediaImageSequenceLoading>(
        asset: any MediaAsset,
        using loader: Loader,
        targetSize: CGSize,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3
    ) async throws {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        makeImageOperation = nil
        restartImageLoadOnAttach = nil
        currentCacheIdentifier = nil
        loadedCacheIdentifier = nil
        loadedStaticSequenceIdentifier = nil
        let sequence = try await loader.loadSequence(from: asset)
        let playbackPlan = await sequence.playbackPlan(levelOfIntegrity: levelOfIntegrity)
        let frameLoader = ImageSequenceFrameLoader(
            sequence: sequence,
            using: loader,
            targetSize: targetSize,
            prefetchCount: prefetchCount,
            playbackFrameIndices: playbackPlan.frameIndices
        )
        guard let firstIndex = playbackPlan.frameIndices.first else { return }
        let firstFrame = try await frameLoader.frame(at: firstIndex)
        try Task.checkCancellation()
        sequencePlayback.play(
            firstFrame: firstFrame,
            frameLoader: frameLoader,
            frameIndices: playbackPlan.frameIndices,
            isAnimated: playbackPlan.isAnimated,
            frameInterval: playbackPlan.frameRate.frameDuration,
            view: self
        )
    }

    /// Loads a request at this view's point bounds and display scale, updating when its cache tier changes.
    public func loadImage<Request: MediaImageRequestProtocol>(
        request: @escaping @MainActor @Sendable (CGSize?) throws -> Request,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil
    ) {
        loadImage(
            using: MediaImageLoader.default,
            request: { targetSize, _ in try request(targetSize) },
            onFailure: onFailure
        )
    }

    /// Loads a request at this view's point bounds and display scale, updating when its cache tier changes.
    public func loadImage<Request: MediaImageRequestProtocol, Loader: MediaImageLoading>(
        using loader: Loader,
        request: @escaping @MainActor @Sendable (CGSize?, CGFloat) throws -> Request,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil
    ) {
        imageLoadTask?.cancel()
        restartImageLoadOnAttach = nil
        sequencePlayback.stop()
        currentCacheIdentifier = nil
        loadedStaticSequenceIdentifier = nil
        imageFailureHandler = onFailure
        makeImageOperation = { targetSize, scale in
            do {
                let imageRequest = try request(targetSize, scale)
                return ImageLoadingOperation(
                    cacheIdentifier: imageRequest.cacheIdentifier,
                    load: { try await loader.load(imageRequest) }
                )
            } catch {
                return nil
            }
        }
        updateImageIfNeeded()
    }

    /// Stops sequence playback while keeping the currently displayed frame.
    public func stopAnimatingSequence() {
        sequencePlayback.stop()
    }

    isolated deinit {
        imageLoadTask?.cancel()
        sequencePlayback.stop()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDisplayScaleChanges()
        layer.addSublayer(imageLayer)
        contentMode = .scaleAspectFit
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDisplayScaleChanges()
        layer.addSublayer(imageLayer)
        contentMode = .scaleAspectFit
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        imageLayer.frame = bounds
        refreshDisplayedLayer()
        updateImageIfNeeded()
    }

    public override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview == nil, superview != nil {
            cancelImageLoadForDetachment()
        }
        super.willMove(toSuperview: newSuperview)
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil, window != nil else { return }
        restartImageLoadIfNeeded()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            cancelImageLoadForDetachment()
            return
        }

        restartImageLoadIfNeeded()
    }

    private func restartImageLoadIfNeeded() {
        if let restartImageLoadOnAttach {
            restartImageLoadOnAttach()
        } else {
            updateImageIfNeeded()
        }
    }

    private func contentsGravity(for contentMode: UIView.ContentMode) -> CALayerContentsGravity {
        switch contentMode {
        case .scaleToFill, .redraw:
            .resize
        case .scaleAspectFit:
            .resizeAspect
        case .scaleAspectFill:
            .resizeAspectFill
        case .center:
            .center
        default:
            .resizeAspect
        }
    }

    fileprivate func setDisplayedImage(_ image: CGImage?) {
        let previousIntrinsicSize = intrinsicContentSize
        displayedImage = image
        refreshDisplayedLayer()
        if Self.intrinsicContentSizeDidChange(from: previousIntrinsicSize, to: intrinsicContentSize) {
            invalidateIntrinsicContentSize()
        }
    }

    static func intrinsicContentSizeDidChange(from previousSize: CGSize, to updatedSize: CGSize) -> Bool {
        previousSize != updatedSize
    }

    private func refreshDisplayedLayer() {
        imageLayer.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contentsScale = 1
        imageLayer.contentsGravity = contentsGravity(for: contentMode)
        imageLayer.contents = displayedImage
        CATransaction.commit()
    }

    private func registerForDisplayScaleChanges() {
        registerForTraitChanges([UITraitDisplayScale.self]) { (self: AsyncImageView, _) in
            self.currentCacheIdentifier = nil
            self.updateImageIfNeeded()
        }
    }

    private func updateImageIfNeeded() {
        guard window != nil, let makeImageOperation else { return }
        let targetSize: CGSize?
        let scale: CGFloat
        if sizingMode == .viewBounds {
            guard bounds.width > 0, bounds.height > 0 else { return }
            targetSize = CGSize(width: bounds.width.rounded(.up), height: bounds.height.rounded(.up))
            scale = traitCollection.displayScale
        } else {
            targetSize = nil
            scale = 1
        }

        guard let operation = makeImageOperation(targetSize, scale) else { return }
        guard operation.cacheIdentifier != currentCacheIdentifier else { return }

        currentCacheIdentifier = operation.cacheIdentifier
        imageLoadTask?.cancel()
        imageLoadTask = nil
        if loadedCacheIdentifier == operation.cacheIdentifier, let displayedImage {
            setDisplayedImage(displayedImage)
            return
        }
        setDisplayedImage(nil)
        imageLoadTask = Task { @MainActor [weak self] in
            do {
                let image = try await operation.load()
                try Task.checkCancellation()
                guard let self,
                      self.currentCacheIdentifier == operation.cacheIdentifier
                else {
                    return
                }
                self.loadedCacheIdentifier = operation.cacheIdentifier
                self.setDisplayedImage(image)
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.currentCacheIdentifier == operation.cacheIdentifier
                else {
                    return
                }
                self.imageFailureHandler?(error)
            }
        }
    }

    private func startImageLoad(
        asset: any MediaAsset,
        levelOfIntegrity: Double,
        prefetchCount: Int,
        onFailure: (@MainActor @Sendable (any Error) -> Void)?
    ) {
        guard window != nil, imageLoadTask == nil else { return }
        imageLoadTask?.cancel()
        sequencePlayback.stop()

        let scale = traitCollection.displayScale
        let targetSize = CGSize(
            width: (bounds.width * scale).rounded(.up),
            height: (bounds.height * scale).rounded(.up)
        )
        let sequenceIdentifier = "\(asset.uniqueKey)|\(targetSize.width)x\(targetSize.height)|integrity:\(levelOfIntegrity)"
        guard loadedStaticSequenceIdentifier != sequenceIdentifier || image == nil else { return }
        let loader = MediaImageLoader.default
        imageLoadTask = Task { @MainActor [weak self] in
            do {
                let sequence = try await loader.loadSequence(from: asset)
                let playbackPlan = await sequence.playbackPlan(levelOfIntegrity: levelOfIntegrity)
                let frameLoader = ImageSequenceFrameLoader(
                    sequence: sequence,
                    using: loader,
                    targetSize: targetSize,
                    prefetchCount: prefetchCount,
                    playbackFrameIndices: playbackPlan.frameIndices
                )
                guard let firstIndex = playbackPlan.frameIndices.first else { return }
                let firstFrame: CGImage
                do {
                    firstFrame = try await frameLoader.frame(at: firstIndex)
                } catch {
                    await frameLoader.cancel()
                    throw error
                }
                try Task.checkCancellation()
                guard let self else {
                    await frameLoader.cancel()
                    return
                }
                self.loadedStaticSequenceIdentifier = !playbackPlan.isAnimated
                    ? sequenceIdentifier
                    : nil
                self.sequencePlayback.play(
                    firstFrame: firstFrame,
                    frameLoader: frameLoader,
                    frameIndices: playbackPlan.frameIndices,
                    isAnimated: playbackPlan.isAnimated,
                    frameInterval: playbackPlan.frameRate.frameDuration,
                    view: self
                )
            } catch is CancellationError {
                return
            } catch {
                onFailure?(error)
            }
        }
    }

    private func cancelImageLoadForDetachment() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        currentCacheIdentifier = nil
        sequencePlayback.stop()
    }
}

private struct ImageLoadingOperation {
    let cacheIdentifier: String
    let load: @MainActor @Sendable () async throws -> CGImage
}

@MainActor
private final class ImageSequencePlayback {
    private weak var view: AsyncImageView?
    private var updateLink: UIUpdateLink?
    private var frameLoadingTask: Task<Void, Never>?
    private var loadFrame: (@MainActor @Sendable (Int) async throws -> CGImage)?
    private var cancelFrameLoading: (@Sendable () async -> Void)?
    private var frameIndices: [Int] = []
    private var frameInterval: TimeInterval = ImageSequenceFrameRate.fps10.frameDuration
    private var startTimestamp: CFTimeInterval?
    private var displayedPosition = 0
    private var desiredPosition = 0

    func play<Loader: MediaImageLoading>(
        firstFrame: CGImage,
        frameLoader: ImageSequenceFrameLoader<Loader>,
        frameIndices: [Int],
        isAnimated: Bool,
        frameInterval: TimeInterval,
        view: AsyncImageView
    ) {
        stop()
        self.view = view
        self.frameInterval = frameInterval
        self.frameIndices = frameIndices
        self.displayedPosition = 0
        self.desiredPosition = 0
        self.loadFrame = { index in try await frameLoader.frame(at: index) }
        self.cancelFrameLoading = { await frameLoader.cancel() }
        view.setDisplayedImage(firstFrame)

        guard isAnimated else {
            let cancelFrameLoading = self.cancelFrameLoading
            self.cancelFrameLoading = nil
            loadFrame = nil
            self.frameIndices = []
            if let cancelFrameLoading {
                Task { await cancelFrameLoading() }
            }
            return
        }

        let updateLink = UIUpdateLink(view: view) { [weak self] _, updateInfo in
            self?.updateLinkDidFire(updateInfo)
        }
        updateLink.requiresContinuousUpdates = true
        updateLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 1,
            maximum: Float(1 / frameInterval),
            preferred: Float(1 / frameInterval)
        )
        updateLink.isEnabled = true
        self.updateLink = updateLink
    }

    func stop() {
        updateLink?.isEnabled = false
        updateLink = nil
        frameLoadingTask?.cancel()
        frameLoadingTask = nil
        let cancelFrameLoading = self.cancelFrameLoading
        self.cancelFrameLoading = nil
        loadFrame = nil
        frameIndices = []
        startTimestamp = nil
        view = nil
        if let cancelFrameLoading {
            Task { await cancelFrameLoading() }
        }
    }

    private func updateLinkDidFire(_ updateInfo: UIUpdateInfo) {
        guard !frameIndices.isEmpty else { return }
        guard let startTimestamp else {
            self.startTimestamp = updateInfo.modelTime
            return
        }

        let elapsed = max(0, updateInfo.modelTime - startTimestamp)
        let position = Int(elapsed / frameInterval) % frameIndices.count
        desiredPosition = position
        guard position != displayedPosition,
              frameLoadingTask == nil,
              let loadFrame
        else {
            return
        }

        let index = frameIndices[position]
        frameLoadingTask = Task { @MainActor [weak self] in
            defer { self?.frameLoadingTask = nil }
            do {
                let image = try await loadFrame(index)
                try Task.checkCancellation()
                guard let self, self.desiredPosition == position else { return }
                self.view?.setDisplayedImage(image)
                self.displayedPosition = position
            } catch is CancellationError {
                return
            } catch {
                self?.stop()
            }
        }
    }
}
#endif
