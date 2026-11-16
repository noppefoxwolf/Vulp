import Foundation
import Vulp
import VulpUI
import Testing

private func isMainThread() -> Bool { Thread.isMainThread }

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
@Test func uiKitAsyncPlaceholderDisplaysWithoutWaitingForLayout() async throws {
    let image = try await PlatformImageFixture.image()
    let view = AsyncImageView()
    view.loadImage(url: URL(string: "https://example.com/image.png")!, placeholder: {
        #expect(!isMainThread())
        return image
    })
    try await Task.sleep(for: .milliseconds(50))
    #expect(view.image === image)
}

@MainActor
@Test func uiKitAssignedImageSupersedesPendingPlaceholder() async throws {
    let image = try await PlatformImageFixture.image()
    let view = AsyncImageView()
    view.loadImage(url: URL(string: "https://example.com/image.png")!, placeholder: {
        try? await Task.sleep(for: .milliseconds(20))
        return image
    })
    view.image = nil
    try await Task.sleep(for: .milliseconds(50))
    #expect(view.image == nil)
}
@MainActor
@Test func uiKitLoadedImageSupersedesPendingPlaceholder() async throws {
    let image = try await PlatformImageFixture.image()
    let placeholder = try await PlatformImageFixture.image()
    let view = AsyncImageView()
    view.loadImage(url: URL(string: "https://example.com/image.png")!, placeholder: {
        try? await Task.sleep(for: .milliseconds(20))
        return placeholder
    })
    view.displayLoadedContent(.still(image), cacheIdentifier: "loaded")
    try await Task.sleep(for: .milliseconds(50))
    #expect(view.image === image)
}
#endif
