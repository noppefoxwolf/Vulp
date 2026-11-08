import Foundation

/// Stores encoded image sources independently from decoded, processed images.
public protocol ImageDataCache: Sendable {
    func data(forKey key: String) async -> Data?
    func insert(_ data: Data, forKey key: String) async
    func removeData(forKey key: String) async
    func removeAllData() async
}
