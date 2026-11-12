import Foundation

actor AssetDataResultCache {
    private let dataCache: any AssetDataCache
    private var failures: [String: any Error] = [:]

    init(dataCache: any AssetDataCache) {
        self.dataCache = dataCache
    }

    func fileURL(forKey key: String) async -> URL? {
        let url = await dataCache.fileURL(forKey: key)
        if url != nil {
            failures.removeValue(forKey: key)
        }
        return url
    }

    func failure(forKey key: String) -> (any Error)? {
        failures[key]
    }

    func insert(_ data: Data, forKey key: String) async -> URL? {
        let url = await dataCache.insert(data, forKey: key)
        failures.removeValue(forKey: key)
        return url
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
