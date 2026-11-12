import Foundation

public protocol ImageCache: Sendable {
    func image(forKey key: String) async -> MediaImage?
    func insert(_ image: MediaImage, forKey key: String) async
    func removeImage(forKey key: String) async
    func removeAllImages() async
}

public protocol MemoryImageCache: ImageCache {
    func handleMemoryWarning() async
}

public protocol SharedImageCache: ImageCache {
    func pruneImages(olderThan date: Date) async
}
