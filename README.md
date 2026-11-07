# MediaLoader

MediaLoader is an image and video thumbnail loading library built with Swift Concurrency. It handles downloading, decoding, resizing, and caching, with integrations for SwiftUI, UIKit, and AppKit.

## Features

- Load remote URLs, local files, and encoded `Data` through a common `MediaAsset` interface
- Load animated images such as GIFs frame by frame and play them incrementally
- Generate thumbnails from video URLs with AVFoundation
- Downsample during decoding and resize images to requested dimensions
- LRU cache for decoded images and a disk cache for encoded source data with configurable size and age limits
- Deduplicate concurrent fetches for the same asset and image request
- Reuse cached images through request size bucketing
- Display APIs for SwiftUI, UIKit, and AppKit
- Compose custom assets, downloaders, decoders, processors, and caches

## Requirements

- Swift 6.4+
- iOS 16+
- macOS 14+

## Installation

Add this repository in Xcode with **File > Add Package Dependencies…**, then select the products your target needs:

- `MediaLoader`: the loading pipeline
- `MediaLoader_SwiftUI`: SwiftUI views
- `MediaLoader_UIKit`: the UIKit `ImageView`
- `MediaLoader_AppKit`: AppKit views
- `MediaLoaderUI`: re-exports the UI products above

## Quick start

### UIKit

Import `MediaLoaderUI` and use its UIKit `ImageView`. Call `loadImage(url:)` to load a URL at the view's size; animated sources play incrementally.

```swift
import MediaLoaderUI
import UIKit

let url = URL(string: "https://example.com/photo.jpg")!
let imageView = ImageView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
imageView.loadImage(url: url)
```

Call it after the view has its final bounds. The view owns and cancels its loading task when a new image is requested or its image is replaced. For full control over request size, caching, and the loader, use the request-builder overload. `MediaImageLoader.default` is preconfigured with URLSession, ImageIO, AVFoundation, resizing, and an in-memory cache.

### SwiftUI

```swift
import MediaLoaderUI
import SwiftUI

struct RemotePhoto: View {
    var body: some View {
        MediaLoaderUI.AsyncImage(url: URL(string: "https://example.com/photo.jpg")!) {
            ProgressView()
        }
    }
}
```

`MediaLoaderUI.AsyncImage(url:)` sizes the request from its displayed bounds and environment display scale. It accepts an optional failure callback and plays animated sources incrementally. For custom loaders or request options, use one of the request-based initializers.

## Performance-conscious loading

Share a loader across screens and cells instead of creating one for each view. The memory cache stores decoded images, while the disk cache stores encoded source data. If an image is requested at another size, the loader can decode it again from the cached source data without downloading it again.

```swift
import MediaLoader

typealias AppImageLoader = DefaultMediaImageLoader<
    DefaultImageDataDownloader,
    ImageIOImageDecoder,
    ResizeImageProcessor,
    LRUImageCache
>

let imageLoader = AppImageLoader(
    downloader: DefaultImageDataDownloader(),
    decoder: ImageIOImageDecoder(),
    processor: ResizeImageProcessor(),
    cache: LRUImageCache(countLimit: 300),
    dataCache: DiskImageDataCache(
        maxSizeBytes: 200 * 1024 * 1024,
        maxAge: 14 * 24 * 60 * 60
    )
)
```

For a collection or list, request the **pixel dimensions needed for display**, not the point dimensions. For example, a 150 pt square on a 3x display needs `450 × 450` pixels. `MediaImageRequest` rounds requested dimensions into aspect-ratio-preserving size buckets, allowing nearby requests to share cached results.

```swift
let request = try MediaImageRequest(
    assetHandle: RemoteMediaAsset(url: photoURL),
    targetSize: CGSize(width: 450, height: 450)
)

let image = try await imageLoader.load(request)
```

The standard `ImageIOImageDecoder` downsamples during decoding using the requested size as an upper bound. `ResizeImageProcessor` then produces the final dimensions. Matching request sizes to the display avoids decoding unnecessarily large images for a scrolling list.

## Prefetching with UICollectionView

Use the same loader and request builder for `UICollectionViewDataSourcePrefetching` and cell display. A prefetched request warms the cache for the cell. Cancel prefetch tasks when the collection view reports that an item is no longer needed.

```swift
import MediaLoader
import MediaLoaderUI
import UIKit

final class PhotoCell: UICollectionViewCell {
    let photoView = ImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.frame = contentView.bounds
        photoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(photoView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.frame = contentView.bounds
        photoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(photoView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        photoView.image = nil
    }
}

@MainActor
final class PhotoDataSource: NSObject,
    UICollectionViewDataSource,
    UICollectionViewDataSourcePrefetching
{
    let urls: [URL]
    let loader = MediaImageLoader.default
    private var prefetchTasks: [IndexPath: Task<Void, Never>] = [:]
    private var prefetchIDs: [IndexPath: UUID] = [:]

    init(urls: [URL]) {
        self.urls = urls
    }

    private func request(at indexPath: IndexPath) throws -> MediaImageRequest {
        try MediaImageRequest(
            assetHandle: RemoteMediaAsset(url: urls[indexPath.item]),
            targetSize: CGSize(width: 450, height: 450)
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        urls.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "PhotoCell",
            for: indexPath
        ) as! PhotoCell
        cell.photoView.image = nil

        guard let request = try? request(at: indexPath) else { return cell }
        let loader = self.loader
        cell.photoView.loadImage(using: loader, request: { _, _ in request })
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        for indexPath in indexPaths where prefetchTasks[indexPath] == nil {
            guard let request = try? request(at: indexPath) else { continue }
            let loader = self.loader
            let id = UUID()
            prefetchIDs[indexPath] = id
            prefetchTasks[indexPath] = Task {
                defer {
                    if prefetchIDs[indexPath] == id {
                        prefetchIDs[indexPath] = nil
                        prefetchTasks[indexPath] = nil
                    }
                }
                do {
                    _ = try await loader.load(request)
                } catch is CancellationError {
                    // The item is no longer expected soon.
                } catch {
                    // The cell can retry when it appears.
                }
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        for indexPath in indexPaths {
            prefetchIDs[indexPath] = nil
            prefetchTasks[indexPath]?.cancel()
            prefetchTasks[indexPath] = nil
        }
    }
}
```

The prefetch and cell requests should use the same `asset.uniqueKey`, size, rendering mode, and decoding options so they produce the same cache key. Cancel a cell's load task during reuse so an old result cannot be assigned to a reused cell.

## Animated images

`MediaLoaderUI.AsyncImage` and `ImageView` load and play multi-frame images incrementally. They do not decode every frame up front; by default, the next three frames are prefetched. Lower `prefetchCount` to reduce memory use. Use `levelOfIntegrity` to adjust the playback frame rate.

## Customization

Build a loader from the `MediaImageLoading`, `ImageDataDownloader`, `MediaImageDecoding`, `ImageProcessor`, `ImageCache`, and `ImageDataCache` protocols. Replace components in `DefaultMediaImageLoader` for custom authenticated networking or image processing.

Implement `MediaAsset` to define a stable `uniqueKey`, an optional fallback image, a media type hint, and a way to load the source data.
