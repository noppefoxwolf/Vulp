#if canImport(UIKit)
import UIKit
@_exported import Vulp

/// A layer-backed image view that sizes image requests from its bounds when requested.
@MainActor
public final class AsyncImageView: UIView {
    private let sequencePlayback = ImageSequencePlayback()
    let placeholderLoading = ImagePlaceholderLoading()
    let imageLoading = ImageContentLoading()
    private var displayState: DisplayState = .empty
    private var makeImageOperation: (@MainActor @Sendable (CGSize?, CGFloat) -> ImageLoadingOperation?)?
    private var currentCacheIdentifier: String?
    private var loadedCacheIdentifier: String?
    private var currentSourceIdentifier: String?
    private var lastRequestLayoutKey: RequestLayoutKey?
    private var playbackOptions: PlaybackOptions?
    /// Receives completion of view-managed loads. The caller retains the delegate.
    public weak var delegate: (any AsyncImageViewDelegate)?

    /// Controls request-builder loads and intrinsic sizing; sequence loads use their explicit `targetSize` argument.
    public var sizingMode: ImageViewSizingMode = .viewBounds {
        didSet {
            guard sizingMode != oldValue else { return }
            currentCacheIdentifier = nil
            lastRequestLayoutKey = nil
            invalidateIntrinsicContentSize()
            setNeedsLayout()
            updateImageIfNeeded()
        }
    }

    public var image: CGImage? {
        get { displayState.image }
        set {
            resetForNewImageSource()
            setDisplayedImage(newValue)
        }
    }

    public override var contentMode: UIView.ContentMode {
        didSet {
            guard contentMode != oldValue else { return }
            updateLayerGravity()
        }
    }

    public override var intrinsicContentSize: CGSize {
        // Bound-sized images are measured by Auto Layout; explicit images contribute pixel dimensions as points.
        guard sizingMode == .explicitPixels, let image else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        return CGSize(width: image.width, height: image.height)
    }

    /// Loads a request at this view's point bounds and display scale, playing multiple frames when supported.
    public func loadImage<Request: MediaImageRequestProtocol, Loader: MediaImageLoading>(
        using loader: Loader = MediaImageLoader.default,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        request: @escaping @MainActor @Sendable (CGSize?, CGFloat) throws -> Request
    ) {
        let options = PlaybackOptions(levelOfIntegrity: levelOfIntegrity, prefetchCount: prefetchCount)
        if playbackOptions != options {
            currentCacheIdentifier = nil
        }
        playbackOptions = options
        lastRequestLayoutKey = nil
        makeImageOperation = { targetSize, scale in
            do {
                let imageRequest = try request(targetSize, scale)
                return ImageLoadingOperation(
                    cacheIdentifier: imageRequest.cacheIdentifier,
                    sourceIdentifier: imageRequest.asset.uniqueKey,
                    load: {
                        try await Self.loadImageRequest(
                            imageRequest,
                            using: loader,
                            levelOfIntegrity: levelOfIntegrity,
                            prefetchCount: prefetchCount
                        )
                    }
                )
            } catch {
                return nil
            }
        }
        updateImageIfNeeded()
        if lastRequestLayoutKey == nil {
            // Until the builder can identify the request, supersede any previous work.
            imageLoading.invalidate()
            currentCacheIdentifier = nil
        }
        startPlaceholderIfNeeded()
    }

    /// Stops sequence playback while keeping the currently displayed frame.
    public func stopAnimatingSequence() {
        sequencePlayback.stop()
    }

    isolated deinit {
        imageLoading.invalidate()
        placeholderLoading.clearAsset()
        sequencePlayback.stop()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDisplayScaleChanges()
        layer.contentsScale = 1
        contentMode = .scaleAspectFit
        updateLayerGravity()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDisplayScaleChanges()
        layer.contentsScale = 1
        contentMode = .scaleAspectFit
        updateLayerGravity()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
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
        placeholderLoading.activityState = .active
        updateImageIfNeeded()
        startPlaceholderIfNeeded()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            cancelImageLoadForDetachment()
            return
        }

        placeholderLoading.activityState = .active
        updateImageIfNeeded()
        startPlaceholderIfNeeded()
    }

    func resetForNewImageSource() {
        placeholderLoading.clearAsset()
        imageLoading.invalidate()
        makeImageOperation = nil
        currentCacheIdentifier = nil
        loadedCacheIdentifier = nil
        currentSourceIdentifier = nil
        lastRequestLayoutKey = nil
        playbackOptions = nil
        sequencePlayback.stop()
    }

    /// The async overload shares source selection, but its task remains caller-owned.
    func prepareExplicitImageLoad(sourceIdentifier: String) {
        makeImageOperation = nil
        currentCacheIdentifier = nil
        lastRequestLayoutKey = nil
        playbackOptions = nil
        sequencePlayback.stop()
        selectImageSource(sourceIdentifier)
        startPlaceholderIfNeeded()
    }

    private func selectImageSource(_ sourceIdentifier: String) {
        guard currentSourceIdentifier != sourceIdentifier else { return }
        let isInitialSource = currentSourceIdentifier == nil && !displayState.isLoadedImage
        if !isInitialSource {
            placeholderLoading.resetGeneration()
            setDisplayedImage(nil)
        }
        currentSourceIdentifier = sourceIdentifier
        currentCacheIdentifier = nil
        loadedCacheIdentifier = nil
    }

    func setDisplayedImage(_ image: CGImage?) {
        setDisplayState(image.map(DisplayState.image) ?? .empty)
    }

    func displayPlaceholder(_ image: CGImage?) {
        guard !displayState.isLoadedImage else { return }
        setDisplayState(image.map(DisplayState.placeholder) ?? .empty)
    }

    func startPlaceholderIfNeeded() {
        guard !displayState.isLoadedImage else { return }
        placeholderLoading.startIfNeeded()
    }

    private func setDisplayState(_ state: DisplayState) {
        let previousIntrinsicSize = intrinsicContentSize
        let contentsChanged = displayState.image !== state.image
        displayState = state
        if contentsChanged {
            updateDisplayedContents()
        }
        if Self.intrinsicContentSizeDidChange(from: previousIntrinsicSize, to: intrinsicContentSize) {
            invalidateIntrinsicContentSize()
        }
    }

    static func intrinsicContentSizeDidChange(from previousSize: CGSize, to updatedSize: CGSize) -> Bool {
        previousSize != updatedSize
    }

    func displayLoadedContent(
        _ content: ImageLoadingResult,
        cacheIdentifier: String,
        notifyCompletion: Bool = true
    ) {
        placeholderLoading.cancelGeneration()
        switch content {
        case .still(let image):
            loadedCacheIdentifier = cacheIdentifier
            setDisplayedImage(image)
            if notifyCompletion {
                delegate?.asyncImageView(self, didComplete: .success(image))
            }
        case .sequence(let playback):
            loadedCacheIdentifier = nil
            sequencePlayback.play(playback, view: self)
            if notifyCompletion {
                delegate?.asyncImageView(self, didComplete: .success(playback.firstFrame))
            }
        }
    }

    private func updateDisplayedContents() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = displayState.image
        CATransaction.commit()
    }

    private func registerForDisplayScaleChanges() {
        registerForTraitChanges([UITraitDisplayScale.self]) { (self: AsyncImageView, _) in
            self.currentCacheIdentifier = nil
            self.updateImageIfNeeded()
        }
    }

    private func updateImageIfNeeded() {
        guard let makeImageOperation else { return }
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

        let layoutKey = RequestLayoutKey(targetSize: targetSize, scale: scale)
        guard layoutKey != lastRequestLayoutKey else { return }

        guard let operation = makeImageOperation(targetSize, scale) else { return }
        selectImageSource(operation.sourceIdentifier)
        startPlaceholderIfNeeded()
        guard window != nil else { return }
        lastRequestLayoutKey = layoutKey
        guard operation.cacheIdentifier != currentCacheIdentifier else { return }

        currentCacheIdentifier = operation.cacheIdentifier
        sequencePlayback.stop()
        if loadedCacheIdentifier == operation.cacheIdentifier, let image = displayState.image {
            imageLoading.invalidate()
            setDisplayedImage(image)
            return
        }
        imageLoading.start({ [weak self] in
            if let self {
                self.delegate?.asyncImageViewDidStartLoading(self)
            } else {
                throw CancellationError()
            }
            try Task.checkCancellation()
            return try await operation.load()
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let content):
                self.displayLoadedContent(content, cacheIdentifier: operation.cacheIdentifier)
            case .failure(let error):
                self.currentCacheIdentifier = nil
                if !(error is CancellationError) {
                    self.delegate?.asyncImageView(self, didComplete: .failure(error))
                }
            }
        }
    }

    private enum DisplayState {
        case empty
        case placeholder(CGImage)
        case image(CGImage)

        var image: CGImage? {
            switch self {
            case .empty: nil
            case .placeholder(let image), .image(let image): image
            }
        }

        var isLoadedImage: Bool {
            if case .image = self { true } else { false }
        }
    }

    private struct PlaybackOptions: Equatable {
        let levelOfIntegrity: Double
        let prefetchCount: Int
    }

    private struct RequestLayoutKey: Equatable {
        let targetSize: CGSize?
        let scale: CGFloat
    }

    static func loadImageRequest<Request: MediaImageRequestProtocol, Loader: MediaImageLoading>(
        _ request: Request,
        using loader: Loader,
        levelOfIntegrity: Double,
        prefetchCount: Int
    ) async throws -> ImageLoadingResult {
        if case .firstFrame = request.decodingOptions,
           let playback = try await sequencePlaybackOperation(
               using: loader,
               asset: request.asset,
               targetSize: request.targetSize,
               levelOfIntegrity: levelOfIntegrity,
               prefetchCount: prefetchCount
           ) {
            return .sequence(playback)
        }

        return .still(try await loader.load(request))
    }

    private static func sequencePlaybackOperation<Loader: MediaImageLoading>(
        using loader: Loader,
        asset: any MediaAsset,
        targetSize: CGSize,
        levelOfIntegrity: Double,
        prefetchCount: Int
    ) async throws -> SequencePlaybackOperation? {
        let sequence: ImageSequence
        do {
            sequence = try await loader.loadSequence(from: asset)
        } catch ImageSequenceError.unsupportedMediaSource {
            return nil
        }

        let plan = await sequence.playbackPlan(levelOfIntegrity: levelOfIntegrity)
        guard plan.isAnimated, let firstIndex = plan.frameIndices.first else { return nil }

        let frameLoader = ImageSequenceFrameLoader(
            sequence: sequence,
            using: loader,
            targetSize: targetSize,
            prefetchCount: prefetchCount,
            playbackFrameIndices: plan.frameIndices
        )
        do {
            let firstFrame = try await frameLoader.frame(at: firstIndex)
            return SequencePlaybackOperation(
                firstFrame: firstFrame,
                frameIndices: plan.frameIndices,
                frameInterval: plan.frameRate.frameDuration,
                loadFrame: { index in try await frameLoader.frame(at: index) },
                cancelFrameLoading: { await frameLoader.cancel() }
            )
        } catch {
            await frameLoader.cancel()
            throw error
        }
    }

    private func cancelImageLoadForDetachment() {
        placeholderLoading.activityState = .inactive
        imageLoading.cancelManagedLoad()
        currentCacheIdentifier = nil
        lastRequestLayoutKey = nil
        sequencePlayback.stop()
    }
}

private struct ImageLoadingOperation {
    let cacheIdentifier: String
    let sourceIdentifier: String
    let load: @MainActor @Sendable () async throws -> ImageLoadingResult
}

enum ImageLoadingResult {
    case still(CGImage)
    case sequence(SequencePlaybackOperation)
}

struct SequencePlaybackOperation {
    let firstFrame: CGImage
    let frameIndices: [Int]
    let frameInterval: TimeInterval
    let loadFrame: @MainActor @Sendable (Int) async throws -> CGImage
    let cancelFrameLoading: @Sendable () async -> Void
}

#endif
