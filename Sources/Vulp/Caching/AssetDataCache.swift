import Foundation

/// Stores encoded asset sources independently from decoded, processed images.
public protocol AssetDataCache: Sendable {
    /// Returns a local file URL for a cached asset source.
    func fileURL(forKey key: String) async -> URL?
    /// Stores source data and returns its local file URL when available.
    func insert(_ data: Data, forKey key: String) async -> URL?
    /// Indicates whether this cache can adopt temporary files.
    var supportsFileMoves: Bool { get }
    /// Consumes the source on success and returns its cached URL.
    func moveFile(at source: URL, forKey key: String) async -> URL?
    func removeData(forKey key: String) async
    func removeAllData() async
}

public extension AssetDataCache {
    var supportsFileMoves: Bool { false }
    func moveFile(at source: URL, forKey key: String) async -> URL? { nil }
}
