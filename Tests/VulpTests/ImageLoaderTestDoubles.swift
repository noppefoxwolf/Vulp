import Foundation
import Vulp

actor CountingAssetDownloader: AssetDataDownloader {
    private let delay: Duration
    private(set) var callCount = 0
    private(set) var cancellationCount = 0
    private(set) var lastPriority: TaskPriority?

    init(delay: Duration = .milliseconds(40)) {
        self.delay = delay
    }

    func download(from url: URL) async throws -> Data {
        callCount += 1
        lastPriority = Task.currentPriority
        do {
            try await Task.sleep(for: delay)
        } catch {
            cancellationCount += 1
            throw error
        }
        return TestImageData.png
    }
}

struct FailingAssetDownloader: AssetDataDownloader {
    func download(from url: URL) async throws -> Data {
        throw TestDownloadFailure.failed
    }
}

enum TestDownloadFailure: Error {
    case failed
}
