import Foundation
import Vulp
import VulpUI
import Testing

private enum PlatformImageFixture {
    static func image() async throws -> MediaImage {
        let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VulpUITests-\(UUID().uuidString)", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        return try await ImageIOImageDecoder().decode(from: url, options: .firstFrame, maximumPixelDimension: nil)
    }
}

#if canImport(AppKit)
import AppKit

@MainActor
@Test func appKitImageViewDisplaysAssignedImage() async throws {
    let image = try await PlatformImageFixture.image()
    let view = ImageView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
    view.contentMode = .center

    view.image = image

    #expect(view.image === image)
    #expect(view.subviews.count == 1)
    #expect(view.contentMode == .center)
}
#endif

#if canImport(UIKit)
import UIKit
@testable import Vulp_UIKit

@MainActor
@Test func uiKitIntrinsicSizeInvalidationOnlyWhenSizeChanges() {
    let noIntrinsicMetric = CGSize(
        width: UIView.noIntrinsicMetric,
        height: UIView.noIntrinsicMetric
    )

    #expect(!AsyncImageView.intrinsicContentSizeDidChange(from: noIntrinsicMetric, to: noIntrinsicMetric))
    #expect(!AsyncImageView.intrinsicContentSizeDidChange(from: CGSize(width: 40, height: 30), to: CGSize(width: 40, height: 30)))
    #expect(AsyncImageView.intrinsicContentSizeDidChange(from: CGSize(width: 40, height: 30), to: CGSize(width: 41, height: 30)))
    #expect(AsyncImageView.intrinsicContentSizeDidChange(from: CGSize(width: 40, height: 30), to: noIntrinsicMetric))
}

@MainActor
@Test func uiKitAsyncImageViewDisplaysAssignedImage() async throws {
    let image = try await PlatformImageFixture.image()
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))

    view.image = image

    #expect(view.image === image)
    #expect(view.subviews.isEmpty)
    #expect(view.contentMode == .scaleAspectFit)
}
@MainActor
final class ImageViewCompletionDelegate: AsyncImageViewDelegate {
    let completion: @MainActor (Result<CGImage, any Error>) -> Void

    init(_ completion: @escaping @MainActor (Result<CGImage, any Error>) -> Void) {
        self.completion = completion
    }

    func asyncImageViewDidStartLoading(_ imageView: AsyncImageView) {}

    func asyncImageView(_ imageView: AsyncImageView, didComplete result: Result<CGImage, any Error>) {
        completion(result)
    }
}

@MainActor
@Test func uiKitImageViewDoesNotRetainDelegate() {
    let view = AsyncImageView()
    var delegate: ImageViewCompletionDelegate? = ImageViewCompletionDelegate { _ in }
    view.delegate = delegate
    #expect(view.delegate === delegate)
    delegate = nil
    #expect(view.delegate == nil)
}

@MainActor
@Test func uiKitImageViewNotifiesDelegateAfterDisplayingImage() async throws {
    let view = AsyncImageView()
    let image = try await PlatformImageFixture.image()
    var count = 0
    let delegate = ImageViewCompletionDelegate { result in
        #expect(view.image === image)
        #expect((try? result.get()) === image)
        count += 1
    }
    view.delegate = delegate
    view.displayLoadedContent(.still(image), cacheIdentifier: "delegate")
    #expect(count == 1)
    view.displayLoadedContent(.still(image), cacheIdentifier: "explicit", notifyCompletion: false)
    #expect(count == 1)
    withExtendedLifetime(delegate) {}
}
#endif
