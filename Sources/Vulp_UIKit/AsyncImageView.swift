#if canImport(UIKit)
import UIKit
@_exported import Vulp

/// A layer-backed image view that sizes image requests from its bounds when requested.
@MainActor
public final class AsyncImageView: UIView {
    private let sequencePlayback = ImageSequencePlayback()
    let placeholderLoading = ImagePlaceholderLoading()
    private var displayedImage: CGImage?
    private var makeImageOperation: (@MainActor @Sendable (CGSize?, CGFloat) -> ImageLoadingOperation?)?
    private var currentCacheIdentifier: String?
    private var loadedCacheIdentifier: String?
    private var currentSourceIdentifier: String?
    private var lastRequestLayoutKey: RequestLayoutKey?
    private var imageLoadTask: Task<Void, Never>?
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
        placeholder: (@Sendable () async throws -> CGImage?)? = nil,
        request: @escaping @MainActor @Sendable (CGSize?, CGFloat) throws -> Request,
        onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)? = nil
    ) {
        resetForNewImageSource()
        setDisplayedImage(nil)
        imageCompletionHandler = onCompletion
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
        placeholderLoading.start(placeholder) { [weak self] image in
            self?.setDisplayedImage(image)
        }
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
        updateImageIfNeeded()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            cancelImageLoadForDetachment()
            return
        }

        updateImageIfNeeded()
    }

    func resetForNewImageSource() {
        placeholderLoading.cancel()
        cancelImageLoadTask()
        makeImageOperation = nil
        currentCacheIdentifier = nil
        loadedCacheIdentifier = nil
        currentSourceIdentifier = nil
        lastRequestLayoutKey = nil
        sequencePlayback.stop()
    }

    func setInitialPlaceholder(_ placeholder: (@Sendable () async throws -> CGImage?)?) {
        setDisplayedImage(nil)
        placeholderLoading.start(placeholder) { [weak self] image in
            self?.setDisplayedImage(image)
        }
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

        let layoutKey = RequestLayoutKey(targetSize: targetSize, scale: scale)
        guard layoutKey != lastRequestLayoutKey else { return }

        guard let operation = makeImageOperation(targetSize, scale) else { return }
        lastRequestLayoutKey = layoutKey
        if currentSourceIdentifier != operation.sourceIdentifier {
            if currentSourceIdentifier != nil {
                placeholderLoading.cancel()
                setDisplayedImage(nil)
            }
            currentSourceIdentifier = operation.sourceIdentifier
            currentCacheIdentifier = nil
            loadedCacheIdentifier = nil
        }
        guard operation.cacheIdentifier != currentCacheIdentifier else { return }

        currentCacheIdentifier = operation.cacheIdentifier
        cancelImageLoadTask()
        sequencePlayback.stop()
        if loadedCacheIdentifier == operation.cacheIdentifier, let displayedImage {
            setDisplayedImage(displayedImage)
            return
        }
        imageLoadTask = Task { @MainActor [weak self] in
            do {
                let image = try await operation.load()
                try Task.checkCancellation()
                guard let self,
                      self.currentCacheIdentifier == operation.cacheIdentifier
                else {
                    return
                }
                self.displayLoadedContent(image, cacheIdentifier: operation.cacheIdentifier)
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.currentCacheIdentifier == operation.cacheIdentifier
                else {
                    return
                }
                self.imageCompletionHandler?(.failure(error))
            }
        }
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
        cancelImageLoadTask()
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
