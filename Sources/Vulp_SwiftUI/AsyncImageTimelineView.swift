import SwiftUI
import Observation
@_exported import Vulp

/// Loads and displays an image, playing it when the loaded source contains multiple frames.
public struct AsyncImageTimelineView<Loader: MediaImageLoading, Content: View, Placeholder: View>: View {
    public enum SizingMode: String, Sendable {
        case explicitPixels
        case viewBounds
    }

    private let taskIdentifier: String
    private let levelOfIntegrity: Double
    private let loadImages: @MainActor @Sendable () async throws -> [MediaImage]
    private let loadSequence: (@MainActor @Sendable () async throws -> (ImageSequenceFrameLoader<Loader>, ImageSequencePlaybackPlan))?
    private let makeSizedSequence: (@MainActor @Sendable (CGSize, CGFloat) -> (@MainActor @Sendable () async throws -> (ImageSequenceFrameLoader<Loader>, ImageSequencePlaybackPlan))?)?
    private let content: (Image) -> Content
    private let placeholder: Placeholder
    private let onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)?

    public let sizingMode: SizingMode

    private let makeImageOperation: (@MainActor @Sendable (CGSize?, CGFloat) -> ImageLoadingOperation?)?

    @State private var image: MediaImage?
    @State private var sequencePlayback: SequencePlaybackState<Loader>?
    @State private var measuredSize: CGSize = .zero
    // Keeps a successful static image in place when SwiftUI restarts its task on reappearance.
    @State private var loadedTaskIdentifier: String?
    @State private var loadedSourceIdentifier: String?

    /// Loads a single image request.
    public init<Request: MediaImageRequestProtocol>(
        request: Request,
        loader: Loader,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.taskIdentifier = request.cacheIdentifier
        self.levelOfIntegrity = 1
        self.sizingMode = .explicitPixels
        self.makeImageOperation = nil
        self.loadSequence = nil
        self.makeSizedSequence = nil
        self.content = content
        self.loadImages = { [loader, request] in
            [try await loader.load(request)]
        }
        self.placeholder = placeholder()
        self.onCompletion = onCompletion
    }

    /// Loads an image source and plays it if its decoded sequence contains multiple frames.
    public init(
        asset: any MediaAsset,
        loader: Loader,
        targetSize: CGSize,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: () -> Placeholder
    ) where Loader: MediaImageSequenceLoading {
        self.taskIdentifier = "\(asset.uniqueKey)|\(targetSize.width)x\(targetSize.height)|integrity:\(levelOfIntegrity)"
        self.levelOfIntegrity = levelOfIntegrity
        self.sizingMode = .explicitPixels
        self.makeImageOperation = nil
        self.makeSizedSequence = nil
        self.content = content
        self.loadImages = { [] }
        self.loadSequence = { [loader, asset] in
            let sequence = try await loader.loadSequence(from: asset)
            let playbackPlan = await sequence.playbackPlan(levelOfIntegrity: levelOfIntegrity)
            return (
                ImageSequenceFrameLoader(
                    sequence: sequence,
                    using: loader,
                    targetSize: targetSize,
                    prefetchCount: prefetchCount,
                    playbackFrameIndices: playbackPlan.frameIndices
                ),
                playbackPlan
            )
        }
        self.placeholder = placeholder()
        self.onCompletion = onCompletion
    }

    /// Builds a request from explicit pixels or the laid-out point size and display scale, depending on `sizingMode`.
    public init<Request: MediaImageRequestProtocol>(
        loader: Loader,
        sizingMode: SizingMode = .viewBounds,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)? = nil,
        request: @escaping @MainActor @Sendable (CGSize?, CGFloat) throws -> Request,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.taskIdentifier = "sized-image"
        self.levelOfIntegrity = 1
        self.sizingMode = sizingMode
        self.loadSequence = nil
        self.makeSizedSequence = nil
        self.content = content
        self.loadImages = { [] }
        self.makeImageOperation = { targetSize, scale in
            do {
                let imageRequest = try request(targetSize, scale)
                return ImageLoadingOperation(
                    cacheIdentifier: imageRequest.cacheIdentifier,
                    sourceIdentifier: imageRequest.asset.uniqueKey,
                    load: { [loader, imageRequest] in
                        try await loader.load(imageRequest)
                    }
                )
            } catch {
                return nil
            }
        }
        self.placeholder = placeholder()
        self.onCompletion = onCompletion
    }

    public var body: some View {
        if let makeSizedSequence {
            measuredContent {
                if hasMeasuredSize {
                    let sequenceOperation = makeSizedSequence(measuredSize, displayScale)
                    imageContent(
                        for: nil,
                        taskIdentifier: "\(taskIdentifier)|\(measuredSize.width)x\(measuredSize.height)@\(displayScale)",
                        sourceIdentifier: taskIdentifier,
                        sequenceOperation: sequenceOperation
                    )
                } else {
                    placeholder
                }
            }
        } else if let makeImageOperation {
            if sizingMode == .viewBounds {
                measuredContent {
                    if hasMeasuredSize {
                        let operation = makeImageOperation(measuredSize, displayScale)
                        imageContent(
                            for: operation,
                            taskIdentifier: "\(measuredSize.width)x\(measuredSize.height)@\(displayScale)",
                            sourceIdentifier: operation?.sourceIdentifier
                        )
                    } else {
                        placeholder
                    }
                }
            } else {
                let operation = makeImageOperation(nil, 1)
                imageContent(for: operation, taskIdentifier: "fixed")
            }
        } else {
            imageContent(for: nil, taskIdentifier: taskIdentifier)
        }
    }

    @Environment(\.displayScale) private var displayScale

    private var hasMeasuredSize: Bool {
        measuredSize.width > 0 && measuredSize.height > 0
    }

    private func measuredContent<MeasuredContent: View>(
        @ViewBuilder content: () -> MeasuredContent
    ) -> some View {
        ZStack {
            Color.clear
                .allowsHitTesting(false)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onGeometryChange(for: CGSize.self) { geometry in
            CGSize(
                width: geometry.size.width.rounded(.up),
                height: geometry.size.height.rounded(.up)
            )
        } action: { size in
            guard size != measuredSize else { return }
            measuredSize = size
        }
    }

    @ViewBuilder
    private func imageContent(
        for operation: ImageLoadingOperation?,
        taskIdentifier: String,
        sourceIdentifier: String? = nil,
        sequenceOperation: (@MainActor @Sendable () async throws -> (ImageSequenceFrameLoader<Loader>, ImageSequencePlaybackPlan))? = nil
    ) -> some View {
        Group {
            if let sequencePlayback {
                SequencePlaybackView(
                    frameLoader: sequencePlayback.frameLoader,
                    playbackPlan: sequencePlayback.playbackPlan,
                    firstImage: sequencePlayback.firstImage,
                    content: content,
                    onCompletion: onCompletion
                )
            } else if let image {
                content(platformImage(image))
            } else {
                placeholder
            }
        }
        .task(id: operation?.cacheIdentifier ?? taskIdentifier) {
            let activeTaskIdentifier = operation?.cacheIdentifier ?? taskIdentifier
            prepareForSource(sourceIdentifier ?? taskIdentifier)
            if let sequenceOperation {
                do {
                    try await playSequence(using: sequenceOperation, taskIdentifier: activeTaskIdentifier)
                } catch is CancellationError {
                    return
                } catch {
                    onCompletion?(.failure(error))
                }
            } else if let operation {
                await load(operation: operation, taskIdentifier: activeTaskIdentifier)
            } else {
                await load(taskIdentifier: activeTaskIdentifier)
            }
        }
    }

    @MainActor
    private func load(operation: ImageLoadingOperation, taskIdentifier: String) async {
        guard loadedTaskIdentifier != taskIdentifier || image == nil else { return }
        do {
            let loadedImage = try await operation.load()
            try Task.checkCancellation()
            image = loadedImage
            loadedTaskIdentifier = taskIdentifier
            onCompletion?(.success(loadedImage))
        } catch is CancellationError {
            return
        } catch {
            onCompletion?(.failure(error))
        }
    }

    @MainActor
    private func load(taskIdentifier: String) async {
        do {
            if let loadSequence {
                guard loadedTaskIdentifier != taskIdentifier || sequencePlayback != nil || image == nil else {
                    return
                }
                try await playSequence(using: loadSequence, taskIdentifier: taskIdentifier)
                return
            }
            guard loadedTaskIdentifier != taskIdentifier || image == nil else { return }
            let loadedImages = try await loadImages()
            try Task.checkCancellation()
            image = loadedImages.first
            if let image {
                onCompletion?(.success(image))
                loadedTaskIdentifier = taskIdentifier
            }
        } catch is CancellationError {
            return
        } catch {
            onCompletion?(.failure(error))
        }
    }

    @MainActor
    private func prepareForSource(_ sourceIdentifier: String) {
        guard loadedSourceIdentifier != sourceIdentifier else { return }
        image = nil
        sequencePlayback = nil
        loadedTaskIdentifier = nil
        loadedSourceIdentifier = sourceIdentifier
    }

    @MainActor
    private func playSequence(
        using loadSequence: @MainActor @Sendable () async throws -> (ImageSequenceFrameLoader<Loader>, ImageSequencePlaybackPlan),
        taskIdentifier: String
    ) async throws {
        let (frameLoader, playbackPlan) = try await loadSequence()
        try await withTaskCancellationHandler {
            do {
                guard let firstIndex = playbackPlan.frameIndices.first else {
                    await frameLoader.cancel()
                    return
                }
                let firstImage = try await frameLoader.frame(at: firstIndex)
                try Task.checkCancellation()
                guard playbackPlan.isAnimated else {
                    image = firstImage
                    sequencePlayback = nil
                    onCompletion?(.success(firstImage))
                    loadedTaskIdentifier = taskIdentifier
                    await frameLoader.cancel()
                    return
                }
                image = nil
                loadedTaskIdentifier = nil
                sequencePlayback = SequencePlaybackState(
                    frameLoader: frameLoader,
                    playbackPlan: playbackPlan,
                    firstImage: firstImage
                )
            } catch {
                await frameLoader.cancel()
                throw error
            }
        } onCancel: {
            Task { await frameLoader.cancel() }
        }
    }
}

/// Convenience initializers that pass the loaded image through without modifiers.
public extension AsyncImageTimelineView where Content == Image {
    init<Request: MediaImageRequestProtocol>(
        request: Request,
        loader: Loader,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.init(
            request: request,
            loader: loader,
            onCompletion: onCompletion,
            content: { $0 },
            placeholder: placeholder
        )
    }

    init(
        asset: any MediaAsset,
        loader: Loader,
        targetSize: CGSize,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) where Loader: MediaImageSequenceLoading {
        self.init(
            asset: asset,
            loader: loader,
            targetSize: targetSize,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount,
            onCompletion: onCompletion,
            content: { $0 },
            placeholder: placeholder
        )
    }

    init<Request: MediaImageRequestProtocol>(
        loader: Loader,
        sizingMode: SizingMode = .viewBounds,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)? = nil,
        request: @escaping @MainActor @Sendable (CGSize?, CGFloat) throws -> Request,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.init(
            loader: loader,
            sizingMode: sizingMode,
            onCompletion: onCompletion,
            request: request,
            content: { $0 },
            placeholder: placeholder
        )
    }
}

private struct SequencePlaybackState<Loader: MediaImageLoading> {
    let frameLoader: ImageSequenceFrameLoader<Loader>
    let playbackPlan: ImageSequencePlaybackPlan
    let firstImage: MediaImage
}

private struct SequencePlaybackView<Loader: MediaImageLoading, Content: View>: View {
    @State private var model: SequencePlaybackModel<Loader>
    private let content: (Image) -> Content

    init(
        frameLoader: ImageSequenceFrameLoader<Loader>,
        playbackPlan: ImageSequencePlaybackPlan,
        firstImage: MediaImage,
        content: @escaping (Image) -> Content,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)?
    ) {
        self.content = content
        _model = State(
            initialValue: SequencePlaybackModel(
                frameLoader: frameLoader,
                playbackPlan: playbackPlan,
                firstImage: firstImage,
                onCompletion: onCompletion
            )
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: model.playbackPlan.frameRate.frameDuration)) { timeline in
            let position = model.position(at: timeline.date)
            content(platformImage(model.image))
                .onChange(of: position, initial: true) { _, position in
                    model.requestFrame(at: position)
                }
        }
        .onDisappear {
            model.stop()
        }
    }
}

@MainActor
@Observable
private final class SequencePlaybackModel<Loader: MediaImageLoading> {
    let playbackPlan: ImageSequencePlaybackPlan
    var image: MediaImage

    @ObservationIgnored private let frameLoader: ImageSequenceFrameLoader<Loader>
    @ObservationIgnored private let startDate = Date.now
    @ObservationIgnored private let onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)?
    @ObservationIgnored private var desiredPosition = 0
    @ObservationIgnored private var displayedPosition = 0
    @ObservationIgnored private var frameLoadingTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = true

    init(
        frameLoader: ImageSequenceFrameLoader<Loader>,
        playbackPlan: ImageSequencePlaybackPlan,
        firstImage: MediaImage,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)?
    ) {
        self.frameLoader = frameLoader
        self.playbackPlan = playbackPlan
        self.image = firstImage
        self.onCompletion = onCompletion
    }

    func position(at date: Date) -> Int {
        let elapsed = max(0, date.timeIntervalSince(startDate))
        let framePosition = Int(elapsed / playbackPlan.frameRate.frameDuration)
        return framePosition % playbackPlan.frameIndices.count
    }

    func requestFrame(at position: Int) {
        guard isActive else { return }
        desiredPosition = position
        guard position != displayedPosition, frameLoadingTask == nil else { return }

        let frameIndex = playbackPlan.frameIndices[position]
        frameLoadingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.frameLoadingTask = nil
                if self.isActive, self.desiredPosition != self.displayedPosition {
                    self.requestFrame(at: self.desiredPosition)
                }
            }

            do {
                let frame = try await self.frameLoader.frame(at: frameIndex)
                try Task.checkCancellation()
                guard self.isActive, self.desiredPosition == position else { return }
                self.image = frame
                self.onCompletion?(.success(frame))
                self.displayedPosition = position
            } catch is CancellationError {
                return
            } catch {
                self.onCompletion?(.failure(error))
                self.stop()
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        frameLoadingTask?.cancel()
        frameLoadingTask = nil
        Task { await frameLoader.cancel() }
    }
}

public extension AsyncImageTimelineView where Loader == DefaultMediaImageLoader {
    /// Loads a URL at the view's size and plays it when it contains multiple frames.
    init(
        url: URL,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        let asset = RemoteMediaAsset(url: url)
        let loader = MediaImageLoader.default
        self.taskIdentifier = asset.uniqueKey
        self.levelOfIntegrity = levelOfIntegrity
        self.sizingMode = .viewBounds
        self.makeImageOperation = nil
        self.loadSequence = nil
        self.loadImages = { [] }
        self.content = content
        self.makeSizedSequence = { pointSize, scale in
            let pixelSize = CGSize(
                width: (pointSize.width * scale).rounded(.up),
                height: (pointSize.height * scale).rounded(.up)
            )
            guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
            return {
                let sequence = try await loader.loadSequence(from: asset)
                let playbackPlan = await sequence.playbackPlan(levelOfIntegrity: levelOfIntegrity)
                return (
                    ImageSequenceFrameLoader(
                        sequence: sequence,
                        using: loader,
                        targetSize: pixelSize,
                        prefetchCount: prefetchCount,
                        playbackFrameIndices: playbackPlan.frameIndices
                    ),
                    playbackPlan
                )
            }
        }
        self.placeholder = placeholder()
        self.onCompletion = onCompletion
    }
}

public extension AsyncImageTimelineView where Loader == DefaultMediaImageLoader, Content == Image {
    init(
        url: URL,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.init(
            url: url,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount,
            onCompletion: onCompletion,
            content: { $0 },
            placeholder: placeholder
        )
    }
}

public extension AsyncImageTimelineView where Loader == DefaultMediaImageLoader, Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
    init(
        url: URL,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onCompletion: (@MainActor @Sendable (Result<MediaImage, any Error>) -> Void)? = nil
    ) {
        self.init(
            url: url,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount,
            onCompletion: onCompletion,
            content: { $0 },
            placeholder: { ProgressView() }
        )
    }
}

private struct ImageLoadingOperation {
    let cacheIdentifier: String
    let sourceIdentifier: String
    let load: @MainActor @Sendable () async throws -> MediaImage
}

private func platformImage(_ image: MediaImage) -> Image {
    Image(decorative: image, scale: 1, orientation: .up)
}
