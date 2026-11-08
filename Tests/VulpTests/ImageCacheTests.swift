import Foundation
import Vulp
import Testing

@Test func memoryCacheStoresAndRemovesImages() async throws {
    let cache = InMemoryImageCache()
    let image = try await TestImageData.image()

    await cache.insert(image, forKey: "one")
    #expect(await cache.image(forKey: "one") === image)

    await cache.removeImage(forKey: "one")
    #expect(await cache.image(forKey: "one") == nil)
}

@Test func memoryWarningClearsMemoryCache() async throws {
    let cache = InMemoryImageCache()
    let image = try await TestImageData.image()
    await cache.insert(image, forKey: "one")

    await cache.handleMemoryWarning()

    #expect(await cache.image(forKey: "one") == nil)
}

@Test func lruCacheEvictsLeastRecentlyUsedImage() async throws {
    let cache = LRUImageCache(countLimit: 2)
    let first = try await TestImageData.image()
    let second = try await TestImageData.image()
    let third = try await TestImageData.image()

    await cache.insert(first, forKey: "first")
    await cache.insert(second, forKey: "second")
    _ = await cache.image(forKey: "first")
    await cache.insert(third, forKey: "third")

    #expect(await cache.image(forKey: "first") === first)
    #expect(await cache.image(forKey: "second") == nil)
    #expect(await cache.image(forKey: "third") === third)
}

@Test func sharedLruCachePrunesEntriesOlderThanDate() async throws {
    let cache = LRUImageCache(countLimit: 2)
    let image = try await TestImageData.image()
    await cache.insert(image, forKey: "old")

    await cache.pruneImages(olderThan: Date().addingTimeInterval(1))

    #expect(await cache.image(forKey: "old") == nil)
}

@Test func layeredCachePromotesUnderlyingHitIntoMemoryCache() async throws {
    let memoryCache = LRUImageCache(countLimit: 2)
    let sharedCache = LRUImageCache(countLimit: 10)
    let layeredCache = LayeredImageCache(mainLRU: memoryCache, underlyingCache: sharedCache)
    let image = try await TestImageData.image()
    await sharedCache.insert(image, forKey: "shared")

    let result = await layeredCache.image(forKey: "shared")

    #expect(result === image)
    #expect(await memoryCache.image(forKey: "shared") === image)
}

@Test func layeredCacheWritesThroughAndMemoryWarningKeepsSharedCopy() async throws {
    let memoryCache = LRUImageCache(countLimit: 2)
    let sharedCache = LRUImageCache(countLimit: 10)
    let layeredCache = LayeredImageCache(mainLRU: memoryCache, underlyingCache: sharedCache)
    let image = try await TestImageData.image()

    await layeredCache.insert(image, forKey: "shared")
    await layeredCache.handleMemoryWarning()

    #expect(await memoryCache.image(forKey: "shared") == nil)
    #expect(await sharedCache.image(forKey: "shared") === image)
}

@Test func layeredCachePruningDoesNotReturnExpiredMemoryEntries() async throws {
    let memoryCache = LRUImageCache(countLimit: 2)
    let sharedCache = LRUImageCache(countLimit: 10)
    let layeredCache = LayeredImageCache(mainLRU: memoryCache, underlyingCache: sharedCache)
    let image = try await TestImageData.image()
    await layeredCache.insert(image, forKey: "expired")

    await layeredCache.pruneImages(olderThan: Date().addingTimeInterval(1))

    #expect(await layeredCache.image(forKey: "expired") == nil)
}
