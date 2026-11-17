#if canImport(UIKit)
import UIKit
@_exported import Vulp

/// A layer-backed image view that sizes image requests from its bounds when requested.
@MainActor
public final class AsyncImageView: UIView {
    private let sequencePlayback = ImageSequencePlayback()
    let placeholderLoading = ImagePlaceholderLoading()
    private var displayedImage: CGImage?
    private(set) var hasLoadedImage = false
    private(set) var isImageLoadDetached = false
    private var makeImageOperation: (@MainActor @Sendable (CGSize?, CGFloat) -> ImageLoadingOperation?)?
    private var currentCacheIdentifier: String?
    private var loadedCacheIdentifier: String?
    private var currentSourceIdentifier: String?
    var placeholderIdentity: ImagePlaceholderIdentity?
    var pendingPlaceholder: PendingImagePlaceholder?
    private var lastRequestLayoutKey: RequestLayoutKey?
    private(set) var imageLoadTask: Task<Void, Never>?
    private(set) var imageLoadGeneration = UUID()
    private var playbackOptions: PlaybackOptions?
    private var imageCompletionHandler: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?

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
        get { displayedImage }
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
    ///
    /// The optional placeholder is generated concurrently with the image load, away from the UI actor.
    /// Errors are ignored, and late results cannot replace a loaded image.
    public func loadImage<Request: MediaImageRequestProtocol, Loader: MediaImageLoading>(
        using loader: Loader = MediaImageLoader.default,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        placeholderID: String? = nil,
        placeholder: (@Sendable () async throws -> CGImage?)? = nil,
        request: @escaping @MainActor @Sendable (CGSize?, CGFloat) throws -> Request,
        onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)? = nil
    ) {
        let options = PlaybackOptions(levelOfIntegrity: levelOfIntegrity, prefetchCount: prefetchCount)
        if playbackOptions != options {
            currentCacheIdentifier = nil
        }
        playbackOptions = options
        lastRequestLayoutKey = nil
        imageCompletionHandler = onCompletion
        pendingPlaceholder = PendingImagePlaceholder(provider: placeholder, id: placeholderID)
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
            invalidateImageRequest()
            currentCacheIdentifier = nil
        }
        if currentSourceIdentifier == nil { configureUnresolvedPlaceholderIfNeeded() }
        resumePlaceholderIfNeeded()
    }

    /// Stops sequence playback while keeping the currently displayed frame.
    public func stopAnimatingSequence() {
        sequencePlayback.stop()
    }

    isolated deinit {
        imageLoadTask?.cancel()
        placeholderLoading.cancel()
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
        isImageLoadDetached = false
        updateImageIfNeeded()
        resumePlaceholderIfNeeded()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            cancelImageLoadForDetachment()
            return
        }

        isImageLoadDetached = false
        updateImageIfNeeded()
        resumePlaceholderIfNeeded()
    }

    func resetForNewImageSource() {
        placeholderLoading.cancel()
        invalidateImageRequest()
        makeImageOperation = nil
        currentCacheIdentifier = nil
        loadedCacheIdentifier = nil
        currentSourceIdentifier = nil
        pendingPlaceholder = nil
        placeholderIdentity = nil
        lastRequestLayoutKey = nil
        playbackOptions = nil
        hasLoadedImage = false
        sequencePlayback.stop()
    }

    private func invalidateImageRequest() {
        imageLoadGeneration = UUID()
        cancelImageLoadTask()
    }

    private func cancelImageLoadTask() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
    }

    func setDisplayedImage(_ image: CGImage?) {
        let previousIntrinsicSize = intrinsicContentSize
        let contentsChanged = displayedImage !== image
        displayedImage = image
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
        placeholderLoading.cancel()
        hasLoadedImage = true
        switch content {
        case .still(let image):
            loadedCacheIdentifier = cacheIdentifier
            setDisplayedImage(image)
            if notifyCompletion {
                imageCompletionHandler?(.success(image))
            }
        case .sequence(let playback):
            loadedCacheIdentifier = nil
            sequencePlayback.play(playback, view: self)
            if notifyCompletion {
                imageCompletionHandler?(.success(playback.firstFrame))
            }
        }
    }

    private func updateDisplayedContents() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = displayedImage
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
        let changesSource = currentSourceIdentifier != operation.sourceIdentifier
        resolvePlaceholderSource(changesSource: changesSource)
        if changesSource {
            hasLoadedImage = false
            currentSourceIdentifier = operation.sourceIdentifier
            currentCacheIdentifier = nil
            loadedCacheIdentifier = nil
        }
        if hasLoadedImage { placeholderLoading.cancel() }
        resumePlaceholderIfNeeded()
        guard window != nil else { return }
        lastRequestLayoutKey = layoutKey
        guard operation.cacheIdentifier != currentCacheIdentifier else { return }

        currentCacheIdentifier = operation.cacheIdentifier
        invalidateImageRequest()
        sequencePlayback.stop()
        if loadedCacheIdentifier == operation.cacheIdentifier, let displayedImage {
            setDisplayedImage(displayedImage)
            return
        }
        let generation = imageLoadGeneration
        imageLoadTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.imageLoadGeneration == generation { self.imageLoadTask = nil }
            }
            do {
                let image = try await operation.load()
                try Task.checkCancellation()
                guard let self,
                      self.imageLoadGeneration == generation
                else {
                    return
                }
                self.displayLoadedContent(image, cacheIdentifier: operation.cacheIdentifier)
            } catch is CancellationError {
                guard let self, self.imageLoadGeneration == generation else { return }
                self.currentCacheIdentifier = nil
            } catch {
                guard let self,
                      self.imageLoadGeneration == generation
                else {
                    return
                }
                self.currentCacheIdentifier = nil
                self.imageCompletionHandler?(.failure(error))
            }
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
        isImageLoadDetached = true
        placeholderLoading.suspend()
        // The async overload is owned by its caller, not by imageLoadTask.
        if imageLoadTask != nil { invalidateImageRequest() }
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
