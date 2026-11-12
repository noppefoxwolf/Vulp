import Foundation

actor AssetDataResultCache {
    private let dataCache: any ImageDataCache
    private var failures: [String: any Error] = [:]

    init(dataCache: any ImageDataCache) {
        self.dataCache = dataCache
    }

    func result(forKey key: String) async -> Result<Data, any Error>? {
        if let data = await dataCache.data(forKey: key) {
            failures.removeValue(forKey: key)
            return .success(data)
        }
        guard let error = failures[key] else { return nil }
        return .failure(error)
    }

    func insert(_ data: Data, forKey key: String) async {
        await dataCache.insert(data, forKey: key)
        failures.removeValue(forKey: key)
    }

    func insertFailure(_ error: any Error, forKey key: String) {
        failures[key] = error
    }

    func removeFailure(forKey key: String) {
        failures.removeValue(forKey: key)
    }

    func removeAll() async {
        await dataCache.removeAllData()
        failures.removeAll()
    }
}
