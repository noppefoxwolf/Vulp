import CryptoKit
import Darwin
import Foundation

/// A disk cache for encoded asset sources with idle-age and total-size limits.
public actor DiskAssetDataCache: AssetDataCache {
    private let directory: URL
    private let maxSizeBytes: Int
    private let maxAge: TimeInterval
    private let agePruneInterval: TimeInterval = 60
    // Mutations await filesystem I/O, so a separate gate protects the byte-count bookkeeping.
    private let writeGate = DiskAssetDataCacheWriteGate()
    private var currentSizeBytes: Int?
    private var lastPrunedAt: Date?

    /// - Parameters:
    ///   - directory: Cache directory. Defaults to the app's caches directory.
    ///   - maxSizeBytes: Maximum total size. Defaults to 100 MiB.
    ///   - maxAge: Maximum time since last access. Defaults to seven days.
    ///   - fileManager: File manager used to resolve the default cache directory.
    public init(
        directory: URL? = nil,
        maxSizeBytes: Int = 100 * 1024 * 1024,
        maxAge: TimeInterval = 7 * 24 * 60 * 60,
        fileManager: FileManager = .default
    ) {
        self.directory = directory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Vulp/Originals", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("Vulp/Originals", isDirectory: true)
        self.maxSizeBytes = max(0, maxSizeBytes)
        self.maxAge = max(0, maxAge)
    }

    public func fileURL(forKey key: String) async -> URL? {
        let url = cacheFileURL(forKey: key)
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modifiedAt) <= maxAge
        else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    public func insert(_ data: Data, forKey key: String) async -> URL? {
        await storeFile(size: data.count, forKey: key) { destination in
            await self.writeCachedAssetData(data, to: destination)
        }
    }

    public nonisolated var supportsFileMoves: Bool { true }

    /// Consumes the source on success. A failed rename leaves it available to the caller.
    @concurrent
    public func moveFile(at source: URL, forKey key: String) async -> URL? {
        guard maxAge > 0, let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return await storeFile(size: size, forKey: key, preserveInsertedFile: true) { destination in
            await self.moveCachedAssetFile(source, to: destination)
        }
    }

    private func storeFile(
        size: Int,
        forKey key: String,
        preserveInsertedFile: Bool = false,
        write: (URL) async -> (succeeded: Bool, previousSize: Int)
    ) async -> URL? {
        guard maxSizeBytes > 0, size <= maxSizeBytes else { return nil }
        await writeGate.acquire()
        let directory = self.directory
        let destination = cacheFileURL(forKey: key)
        let maxSizeBytes = self.maxSizeBytes
        let maxAge = self.maxAge
        let now = Date()

        let directoryReady = await directory.createDirectoryIfNeeded()

        var stored = false
        if directoryReady {
            if currentSizeBytes == nil || shouldPruneExpiredFiles(at: now) {
                currentSizeBytes = await pruneCachedAssetData(
                    in: directory,
                    maxSizeBytes: maxSizeBytes,
                    maxAge: maxAge,
                    at: now
                )
                if currentSizeBytes != nil {
                    lastPrunedAt = now
                }
            }

            let result = await write(destination)
            stored = result.succeeded

            if result.succeeded {
                if let currentSizeBytes {
                    self.currentSizeBytes = max(0, currentSizeBytes - result.previousSize) + size
                }

                // Scan all entries only when the tracked total exceeds the configured limit.
                if currentSizeBytes.map({ $0 > maxSizeBytes }) ?? true {
                    currentSizeBytes = await pruneCachedAssetData(
                        in: directory,
                        maxSizeBytes: maxSizeBytes,
                        maxAge: maxAge,
                        at: now,
                        preserving: preserveInsertedFile ? destination : nil
                    )
                    if currentSizeBytes != nil {
                        lastPrunedAt = now
                    }
                }
            }
        }
        await writeGate.release()
        if preserveInsertedFile { return stored ? destination : nil }
        return await fileURL(forKey: key)
    }

    public func removeData(forKey key: String) async {
        let url = cacheFileURL(forKey: key)
        await writeGate.acquire()
        let result = await removeCachedAssetData(at: url)
        if result.succeeded, let currentSizeBytes {
            self.currentSizeBytes = max(0, currentSizeBytes - result.size)
        }
        await writeGate.release()
    }

    public func removeAllData() async {
        await writeGate.acquire()
        let directory = self.directory
        await directory.removeItemIfPresent()
        // Re-scan on the next write in case the best-effort removal failed.
        currentSizeBytes = nil
        lastPrunedAt = nil
        await writeGate.release()
    }

    private func cacheFileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(digest, isDirectory: false)
    }

    private func shouldPruneExpiredFiles(at date: Date) -> Bool {
        guard let lastPrunedAt else { return true }
        return date.timeIntervalSince(lastPrunedAt) >= agePruneInterval
    }
}

private actor DiskAssetDataCacheWriteGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        waiters.removeFirst().resume()
    }
}

private extension DiskAssetDataCache {
    @concurrent
    func writeCachedAssetData(_ data: Data, to destination: URL) async -> (succeeded: Bool, previousSize: Int) {
        let fileManager = FileManager.default
        do {
            let previousSize = (try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
            try data.write(to: destination, options: .atomic)
            return (true, previousSize)
        } catch {
            return (false, 0)
        }
    }

    @concurrent
    func moveCachedAssetFile(_ source: URL, to destination: URL) async -> (succeeded: Bool, previousSize: Int) {
        let fileManager = FileManager.default
        let previousSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        do {
            try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: source.path)
        } catch {
            return (false, 0)
        }
        let succeeded = rename(source.path, destination.path) == 0
        return (succeeded, previousSize)
    }

    @concurrent
    func removeCachedAssetData(at url: URL) async -> (succeeded: Bool, size: Int) {
        let fileManager = FileManager.default
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        do {
            try fileManager.removeItem(at: url)
            return (true, size)
        } catch {
            return (false, 0)
        }
    }

    @concurrent
    func pruneCachedAssetData(
        in directory: URL,
        maxSizeBytes: Int,
        maxAge: TimeInterval,
        at now: Date,
        preserving preservedURL: URL? = nil
    ) async -> Int? {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let entries = files.compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize
            else { return nil }
            return (url, date, size)
        }.sorted { $0.date > $1.date }

        var totalSize = entries.first { $0.url == preservedURL }?.size ?? 0
        for entry in entries where entry.url != preservedURL {
            if now.timeIntervalSince(entry.date) > maxAge || entry.size > maxSizeBytes - totalSize {
                try? fileManager.removeItem(at: entry.url)
            } else {
                totalSize += entry.size
            }
        }
        return totalSize
    }
}

private extension URL {
    @concurrent
    func createDirectoryIfNeeded() async -> Bool {
        do {
            try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    @concurrent
    func removeItemIfPresent() async {
        try? FileManager.default.removeItem(at: self)
    }
}
