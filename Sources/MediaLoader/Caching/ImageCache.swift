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

/// In-memory least-recently-used cache with age-based pruning.
public actor LRUImageCache: MemoryImageCache, SharedImageCache {
    private struct Entry {
        let image: MediaImage
        let insertedAt: Date
        var accessOrder: UInt64
    }

    private let countLimit: Int
    private var entries: [String: Entry] = [:]
    private var nextAccessOrder: UInt64 = 0

    public init(countLimit: Int = 200) {
        self.countLimit = max(0, countLimit)
    }

    public func image(forKey key: String) async -> MediaImage? {
        guard var entry = entries[key] else { return nil }
        entry.accessOrder = advanceAccessOrder()
        entries[key] = entry
        return entry.image
    }

    public func insert(_ image: MediaImage, forKey key: String) async {
        guard countLimit > 0 else { return }
        entries[key] = Entry(image: image, insertedAt: Date(), accessOrder: advanceAccessOrder())
        while entries.count > countLimit,
              let leastRecentlyUsedKey = entries.min(by: { $0.value.accessOrder < $1.value.accessOrder })?.key {
            entries.removeValue(forKey: leastRecentlyUsedKey)
        }
    }

    public func removeImage(forKey key: String) async {
        entries.removeValue(forKey: key)
    }

    public func removeAllImages() async {
        entries.removeAll(keepingCapacity: false)
    }

    public func handleMemoryWarning() async {
        entries.removeAll(keepingCapacity: false)
    }

    public func pruneImages(olderThan date: Date) async {
        entries = entries.filter { $0.value.insertedAt >= date }
    }

    private func advanceAccessOrder() -> UInt64 {
        nextAccessOrder &+= 1
        return nextAccessOrder
    }
}

/// Backward-compatible name for the default in-memory cache.
public typealias InMemoryImageCache = LRUImageCache
