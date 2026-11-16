#if canImport(UIKit)
import UIKit
import Vulp

@MainActor
final class ImageSequencePlayback {
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

    func play(_ operation: SequencePlaybackOperation, view: AsyncImageView) {
        stop()
        self.view = view
        self.frameInterval = operation.frameInterval
        self.frameIndices = operation.frameIndices
        self.displayedPosition = 0
        self.desiredPosition = 0
        self.loadFrame = operation.loadFrame
        self.cancelFrameLoading = operation.cancelFrameLoading
        view.setDisplayedImage(operation.firstFrame)

        let updateLink = UIUpdateLink(view: view) { [weak self] _, updateInfo in
            self?.updateLinkDidFire(updateInfo)
        }
        updateLink.requiresContinuousUpdates = true
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
