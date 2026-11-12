import Foundation

/// Stores encoded asset sources independently from decoded, processed images.
public protocol AssetDataCache: Sendable {
    /// Returns a local file URL for a cached asset source.
    func fileURL(forKey key: String) async -> URL?
    /// Stores source data and returns its local file URL when available.
    func insert(_ data: Data, forKey key: String) async -> URL?
    func removeData(forKey key: String) async
    func removeAllData() async
}
