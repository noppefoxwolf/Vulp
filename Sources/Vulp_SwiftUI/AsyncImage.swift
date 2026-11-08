import SwiftUI
import Observation
@_exported import Vulp

/// Loads and displays an image, playing it when the loaded source contains multiple frames.
public struct AsyncImage<Loader: MediaImageLoading, Placeholder: View>: View {
    private let taskIdentifier: String
    private let levelOfIntegrity: Double
    private let loadImages: @MainActor @Sendable () async throws -> [MediaImage]
    private let loadSequence: (@MainActor @Sendable () async throws -> (ImageSequenceFrameLoader<Loader>, ImageSequencePlaybackPlan))?
    private let makeSizedSequence: (@MainActor @Sendable (CGSize, CGFloat) -> (@MainActor @Sendable () async throws -> (ImageSequenceFrameLoader<Loader>, ImageSequencePlaybackPlan))?)?
    private let placeholder: Placeholder
    private let onFailure: (@MainActor @Sendable (any Error) -> Void)?

    public let sizingMode: ImageViewSizingMode

    private let makeImageOperation: (@MainActor @Sendable (CGSize?, CGFloat) -> ImageLoadingOperation?)?

    @State private var image: MediaImage?
    @State private var sequencePlayback: SequencePlaybackState<Loader>?

    /// Loads a single image request.
    public init<Request: MediaImageRequestProtocol>(
        request: Request,
        loader: Loader,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.taskIdentifier = request.cacheIdentifier
        self.levelOfIntegrity = 1
        self.sizingMode = .explicitPixels
        self.makeImageOperation = nil
        self.loadSequence = nil
        self.makeSizedSequence = nil
        self.loadImages = { [loader, request] in
            [try await loader.load(request)]
        }
        self.placeholder = placeholder()
        self.onFailure = onFailure
    }

    /// Loads an image source and plays it if its decoded sequence contains multiple frames.
    public init(
        asset: any MediaAsset,
        loader: Loader,
        targetSize: CGSize,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil,
        @ViewBuilder placeholder: () -> Placeholder
    ) where Loader: MediaImageSequenceLoading {
        self.taskIdentifier = "\(asset.uniqueKey)|\(targetSize.width)x\(targetSize.height)|integrity:\(levelOfIntegrity)"
        self.levelOfIntegrity = levelOfIntegrity
        self.sizingMode = .explicitPixels
        self.makeImageOperation = nil
        self.makeSizedSequence = nil
        self.loadImages = { [] }
        self.loadSequence = { [loader, asset] in
            let sequence = try await loader.loadSequence(from: asset)
            let playbackPlan = sequence.playbackPlan(levelOfIntegrity: levelOfIntegrity)
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
        self.onFailure = onFailure
    }

    /// Builds a request from explicit pixels or the laid-out point size and display scale, depending on `sizingMode`.
    public init<Request: MediaImageRequestProtocol>(
        loader: Loader,
        sizingMode: ImageViewSizingMode = .viewBounds,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil,
        request: @escaping @MainActor @Sendable (CGSize?, CGFloat) throws -> Request,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.taskIdentifier = "sized-image"
        self.levelOfIntegrity = 1
        self.sizingMode = sizingMode
        self.loadSequence = nil
        self.makeSizedSequence = nil
        self.loadImages = { [] }
        self.makeImageOperation = { targetSize, scale in
            do {
                let imageRequest = try request(targetSize, scale)
                return ImageLoadingOperation(
                    cacheIdentifier: imageRequest.cacheIdentifier,
                    load: { [loader, imageRequest] in
                        try await loader.load(imageRequest)
                    }
                )
            } catch {
                return nil
            }
        }
        self.placeholder = placeholder()
        self.onFailure = onFailure
    }

    public var body: some View {
        if let makeSizedSequence {
            GeometryReader { geometry in
                let targetSize = CGSize(
                    width: geometry.size.width.rounded(.up),
                    height: geometry.size.height.rounded(.up)
                )
                let sequenceOperation = makeSizedSequence(targetSize, displayScale)
                imageContent(
                    for: nil,
                    taskIdentifier: "\(taskIdentifier)|\(targetSize.width)x\(targetSize.height)@\(displayScale)",
                    sequenceOperation: sequenceOperation
                )
            }
        } else if let makeImageOperation {
            if sizingMode == .viewBounds {
                GeometryReader { geometry in
                    let targetSize = CGSize(
                        width: geometry.size.width.rounded(.up),
                        height: geometry.size.height.rounded(.up)
                    )
                    let operation = makeImageOperation(targetSize, displayScale)
                    imageContent(
                        for: operation,
                        taskIdentifier: "\(targetSize.width)x\(targetSize.height)@\(displayScale)"
                    )
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

    @ViewBuilder
    private func imageContent(
        for operation: ImageLoadingOperation?,
        taskIdentifier: String,
        sequenceOperation: (@MainActor @Sendable () async throws -> (ImageSequenceFrameLoader<Loader>, ImageSequencePlaybackPlan))? = nil
    ) -> some View {
        Group {
            if let sequencePlayback {
                SequencePlaybackView(
                    frameLoader: sequencePlayback.frameLoader,
                    playbackPlan: sequencePlayback.playbackPlan,
                    firstImage: sequencePlayback.firstImage,
                    onFailure: onFailure
                )
            } else if let image {
                PlatformImage(image: image)
            } else {
                placeholder
            }
        }
        .task(id: operation?.cacheIdentifier ?? taskIdentifier) {
            if let sequenceOperation {
                do {
                    try await playSequence(using: sequenceOperation)
                } catch is CancellationError {
                    return
                } catch {
                    onFailure?(error)
                }
            } else if let operation {
                await load(operation: operation)
            } else {
                await load()
            }
        }
    }

    @MainActor
    private func load(operation: ImageLoadingOperation) async {
        image = nil
        sequencePlayback = nil
        do {
            let loadedImage = try await operation.load()
            try Task.checkCancellation()
            image = loadedImage
        } catch is CancellationError {
            return
        } catch {
            onFailure?(error)
        }
    }

    @MainActor
    private func load() async {
        image = nil
        sequencePlayback = nil
        do {
            if let loadSequence {
                try await playSequence(using: loadSequence)
                return
            }
            let loadedImages = try await loadImages()
            try Task.checkCancellation()
            image = loadedImages.first
        } catch is CancellationError {
            return
        } catch {
            onFailure?(error)
        }
    }

    @MainActor
    private func playSequence(
        using loadSequence: @MainActor @Sendable () async throws -> (ImageSequenceFrameLoader<Loader>, ImageSequencePlaybackPlan)
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
                guard Set(playbackPlan.frameIndices).count > 1 else {
                    image = firstImage
                    await frameLoader.cancel()
                    return
                }
                image = nil
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

private struct SequencePlaybackState<Loader: MediaImageLoading> {
    let frameLoader: ImageSequenceFrameLoader<Loader>
    let playbackPlan: ImageSequencePlaybackPlan
    let firstImage: MediaImage
}

private struct SequencePlaybackView<Loader: MediaImageLoading>: View {
    @State private var model: SequencePlaybackModel<Loader>

    init(
        frameLoader: ImageSequenceFrameLoader<Loader>,
        playbackPlan: ImageSequencePlaybackPlan,
        firstImage: MediaImage,
        onFailure: (@MainActor @Sendable (any Error) -> Void)?
    ) {
        _model = State(
            initialValue: SequencePlaybackModel(
                frameLoader: frameLoader,
                playbackPlan: playbackPlan,
                firstImage: firstImage,
                onFailure: onFailure
            )
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: model.playbackPlan.frameRate.frameDuration)) { timeline in
            let position = model.position(at: timeline.date)
            PlatformImage(image: model.image)
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
    @ObservationIgnored private let onFailure: (@MainActor @Sendable (any Error) -> Void)?
    @ObservationIgnored private var desiredPosition = 0
    @ObservationIgnored private var displayedPosition = 0
    @ObservationIgnored private var frameLoadingTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = true

    init(
        frameLoader: ImageSequenceFrameLoader<Loader>,
        playbackPlan: ImageSequencePlaybackPlan,
        firstImage: MediaImage,
        onFailure: (@MainActor @Sendable (any Error) -> Void)?
    ) {
        self.frameLoader = frameLoader
        self.playbackPlan = playbackPlan
        self.image = firstImage
        self.onFailure = onFailure
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
                self.displayedPosition = position
            } catch is CancellationError {
                return
            } catch {
                self.onFailure?(error)
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

public extension AsyncImage where Loader == DefaultMediaImageLoader<
    DefaultImageDataDownloader,
    MediaImageDecoderSet<ImageIOImageDecoder, AVFoundationVideoFrameDecoder>,
    ResizeImageProcessor,
    InMemoryImageCache
> {
    /// Loads a URL at the view's size and plays it when it contains multiple frames.
    init(
        url: URL,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil,
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
        self.makeSizedSequence = { pointSize, scale in
            let pixelSize = CGSize(
                width: (pointSize.width * scale).rounded(.up),
                height: (pointSize.height * scale).rounded(.up)
            )
            guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
            return {
                let sequence = try await loader.loadSequence(from: asset)
                let playbackPlan = sequence.playbackPlan(levelOfIntegrity: levelOfIntegrity)
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
        self.onFailure = onFailure
    }
}

private struct ImageLoadingOperation {
    let cacheIdentifier: String
    let load: @MainActor @Sendable () async throws -> MediaImage
}

private struct PlatformImage: View {
    let image: MediaImage

    var body: some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
        #else
        EmptyView()
        #endif
    }
}
