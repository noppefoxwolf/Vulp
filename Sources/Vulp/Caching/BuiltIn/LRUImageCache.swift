import Foundation

/// In-memory least-recently-used cache with age-based pruning.
public actor LRUImageCache: MemoryImageCache, SharedImageCache {
    private struct Entry {
        let image: MediaImage
        let cost: Int
        let insertedAt: Date
        var accessOrder: UInt64
    }

    private let countLimit: Int
    private let totalCostLimit: Int
    private var entries: [String: Entry] = [:]
    private var nextAccessOrder: UInt64 = 0

    /// Limits both entry count and decoded bitmap bytes (row stride × height).
    /// A zero or negative limit disables storage. Defaults to 100 MiB.
    public init(countLimit: Int = 200, totalCostLimit: Int = 100 * 1024 * 1024) {
        self.countLimit = max(0, countLimit)
        self.totalCostLimit = max(0, totalCostLimit)
    }

    public func image(forKey key: String) async -> MediaImage? {
        guard var entry = entries[key] else { return nil }
        entry.accessOrder = advanceAccessOrder()
        entries[key] = entry
        return entry.image
    }

    public func insert(_ image: MediaImage, forKey key: String) async {
        entries.removeValue(forKey: key)
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard countLimit > 0, totalCostLimit > 0,
              !overflow, cost <= totalCostLimit else { return }

        // Make room before inserting so byte accounting cannot overflow.
        var currentCost = entries.values.reduce(0) { $0 + $1.cost }
        while entries.count >= countLimit || currentCost > totalCostLimit - cost,
              let leastRecentlyUsedKey = entries.min(by: { $0.value.accessOrder < $1.value.accessOrder })?.key {
            if let removed = entries.removeValue(forKey: leastRecentlyUsedKey) {
                currentCost -= removed.cost
            }
        }
        entries[key] = Entry(image: image, cost: cost, insertedAt: Date(), accessOrder: advanceAccessOrder())
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
