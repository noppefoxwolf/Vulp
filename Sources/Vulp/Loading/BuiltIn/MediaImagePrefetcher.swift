import Foundation

/// Manages URL prefetch tasks for a changing prefetch window.
///
/// Starting an already-prefetched URL is a no-op. Stop URLs when they leave
/// the window; completed tasks are removed automatically.
public actor MediaImagePrefetcher {
    private struct Entry: Sendable {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let loader: any MediaImageLoading
    private var tasks: [URL: Entry] = [:]

    public init(loader: any MediaImageLoading = MediaImageLoader.default) {
        self.loader = loader
    }

    /// Starts low-priority prefetches for URLs that are not already in flight.
    public func startPrefetching(with urls: [URL]) {
        for url in urls where tasks[url] == nil {
            let id = UUID()
            let task = loader.prefetch(RemoteMediaAsset(url: url), priority: .background)
            tasks[url] = Entry(id: id, task: task)
            Task {
                await task.value
                finishedPrefetching(url, id: id)
            }
        }
    }

    /// Cancels the prefetch waiters for URLs that left the window.
    public func stopPrefetching(with urls: [URL]) {
        for url in urls {
            tasks.removeValue(forKey: url)?.task.cancel()
        }
    }

    /// Cancels all prefetch waiters managed by this prefetcher.
    public func stopPrefetching() {
        let activeTasks = tasks.values.map(\.task)
        tasks.removeAll(keepingCapacity: false)
        activeTasks.forEach { $0.cancel() }
    }

    private func finishedPrefetching(_ url: URL, id: UUID) {
        guard tasks[url]?.id == id else { return }
        tasks.removeValue(forKey: url)
    }
}
