import Foundation

/// A fast LRU in front of a shared backing cache.
public actor LayeredImageCache: ImageCache {
    private let mainLRU: any MemoryImageCache
    private let underlyingCache: any SharedImageCache

    public init(mainLRU: any MemoryImageCache, underlyingCache: any SharedImageCache) {
        self.mainLRU = mainLRU
        self.underlyingCache = underlyingCache
    }

    public func image(forKey key: String) async -> MediaImage? {
        if let image = await mainLRU.image(forKey: key) {
            return image
        }
        guard let image = await underlyingCache.image(forKey: key) else {
            return nil
        }
        await mainLRU.insert(image, forKey: key)
        return image
    }

    public func insert(_ image: MediaImage, forKey key: String) async {
        await mainLRU.insert(image, forKey: key)
        await underlyingCache.insert(image, forKey: key)
    }

    public func removeImage(forKey key: String) async {
        await mainLRU.removeImage(forKey: key)
        await underlyingCache.removeImage(forKey: key)
    }

    public func removeAllImages() async {
        await mainLRU.removeAllImages()
        await underlyingCache.removeAllImages()
    }

    public func handleMemoryWarning() async {
        await mainLRU.handleMemoryWarning()
    }

    public func pruneImages(olderThan date: Date) async {
        await underlyingCache.pruneImages(olderThan: date)
        await mainLRU.removeAllImages()
    }
}
