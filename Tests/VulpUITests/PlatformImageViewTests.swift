import Foundation
import Vulp
import VulpUI
import Testing

private enum PlatformImageFixture {
    static func image() async throws -> MediaImage {
        let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!
        return try await ImageIOImageDeserializer().deserialize(data)
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

@MainActor
@Test func uiKitAsyncImageViewDisplaysAssignedImage() async throws {
    let image = try await PlatformImageFixture.image()
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))

    view.image = image

    #expect(view.image === image)
    #expect(view.subviews.isEmpty)
    #expect(view.contentMode == .scaleAspectFit)
}
#endif
