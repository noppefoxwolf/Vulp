# Vulp

Vulp is an image and video thumbnail loading library built with Swift Concurrency. It handles downloading, decoding, resizing, and caching, with integrations for SwiftUI, UIKit, and AppKit.

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
- iOS 18+
- macOS 14+

## Installation

Add this repository in Xcode with **File > Add Package Dependencies…**, then select the products your target needs:

- `Vulp`: the loading pipeline
- `Vulp_SwiftUI`: SwiftUI views
- `Vulp_UIKit`: the UIKit `AsyncImageView`
- `Vulp_AppKit`: AppKit views
- `VulpUI`: re-exports the UI products above

## Quick start

### UIKit

Import `VulpUI` and use its UIKit `AsyncImageView`. Call `loadImage(url:)` to load a URL at the view's size; animated sources play incrementally.

```swift
import VulpUI
import UIKit

let url = URL(string: "https://example.com/photo.jpg")!
let imageView = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
imageView.loadImage(url: url)
```

Call it after the view has its final bounds. The view owns and cancels its loading task when a new image is requested or its image is replaced. For full control over request size, caching, and the loader, use the request-builder overload. `MediaImageLoader.default` is preconfigured with URLSession, ImageIO, AVFoundation, resizing, and an in-memory cache.

### SwiftUI

```swift
import VulpUI
import SwiftUI

struct RemotePhoto: View {
    var body: some View {
        VulpUI.AsyncImage(url: URL(string: "https://example.com/photo.jpg")!)
    }
}
```

`VulpUI.AsyncImage(url:)` sizes the request from its displayed bounds and environment display scale. To customize the image or placeholder, pass `content` and `placeholder` closures; the `content` closure receives a SwiftUI `Image`, so apply `.resizable()`, `.scaledToFit()`, or other image modifiers there. It accepts an optional failure callback and plays animated sources incrementally. For custom loaders or request options, use one of the request-based initializers.

The processor downsamples images to the request's bucketed pixel size while preserving their aspect ratio. Choose presentation behavior in the UI: set `UIImageView.contentMode` / `AsyncImageView.contentMode` in UIKit, or use `.scaledToFit()` / `.scaledToFill()` in SwiftUI. Since presentation mode is not part of the request or cache key, the same bucketed image can be reused for either mode.

## Performance-conscious loading

Share a loader across screens and cells instead of creating one for each view. The memory cache stores decoded images, while the disk cache stores encoded source data. If an image is requested at another size, the loader can decode it again from the cached source data without downloading it again. Clear both caches held by the standard loader with `await MediaImageLoader.default.clearCache()`.

```swift
import Vulp

typealias AppImageLoader = DefaultMediaImageLoader<
    DefaultImageDataDownloader,
    ResizeImageProcessor,
    LRUImageCache
>

let imageLoader = AppImageLoader(
    downloader: DefaultImageDataDownloader(),
    decoders: [ImageIOImageDecoder()],
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

The standard `ImageIOImageDecoder` downsamples during decoding using the requested size as an upper bound. `ResizeImageProcessor` applies the request's bucketed size while preserving the source aspect ratio; fit and fill are presentation choices owned by the UI. Matching request sizes to the display avoids decoding unnecessarily large images for a scrolling list. The display layer may scale the processed image to the view's bounds.

## Prefetching with UICollectionView

With `DefaultMediaImageLoader`, use the same asset identity for `UICollectionViewDataSourcePrefetching` and cell display. Prefetch downloads and stores only the encoded source in the disk cache; decoding and resizing happen when the cell requests the image. Cancel prefetch tasks when the collection view reports that an item is no longer needed.

```swift
import Vulp
import VulpUI
import UIKit

final class PhotoCell: UICollectionViewCell {
    let photoView = AsyncImageView()

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
    private var prefetchTasks: [IndexPath: MediaImagePrefetchTask] = [:]

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
            prefetchTasks[indexPath] = loader.prefetch(request)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        for indexPath in indexPaths {
            prefetchTasks[indexPath]?.cancel()
            prefetchTasks[indexPath] = nil
        }
    }
}
```

The prefetch and cell requests should use the same `asset.uniqueKey` so the cell load can reuse the encoded source from disk. Their size, rendering mode, and decoding options may differ because the default loader's prefetch does not create a decoded-image cache entry. Cancel a cell's load task during reuse so an old result cannot be assigned to a reused cell.

`MediaImageLoading.prefetch(_:)` returns a cancellable `MediaImagePrefetchTask` and defaults to `.background` priority. `DefaultMediaImageLoader` downloads only the encoded source into its data cache; custom loaders retain the default image-loading behavior unless they provide their own prefetch implementation. Concurrent source downloads with the same `uniqueKey` share one in-flight operation; different keys are treated as separate assets even when their URLs match. Cancel a prefetch task when an item leaves the prefetch window. The active shared download is cancelled when its last waiter goes away; cancelling one waiter does not interrupt a download still used by another caller. Set an explicit priority for visible work when needed:

```swift
let image = try await loader.load(request, priority: .userInitiated)
```

## Animated images

`VulpUI.AsyncImage` and `AsyncImageView` support animated GIF, APNG, and WebP images. They load and play frames incrementally instead of decoding every frame up front; by default, the next three frames are prefetched. Lower `prefetchCount` to reduce memory use. Use `levelOfIntegrity` to adjust the playback frame rate.

## Customization

Build a loader from the `MediaImageLoading`, `ImageDataDownloader`, `MediaImageDecoding`, `ImageProcessor`, `ImageCache`, and `ImageDataCache` protocols. Every `MediaImageDecoding` implementation must implement `canDecode(data:)` and `canDecode(url:)` so the ordered decoder array can select the right one. Implement `canDecodeSequence(data:)` to opt into animated-image sequence loading. `DefaultMediaImageLoader` uses the first matching decoder for each operation.

```swift
struct CustomImageDecoder: MediaImageDecoding {
    func canDecode(data: Data) async -> Bool {
        data.starts(with: Data("CUSTOM".utf8))
    }

    func canDecode(url: URL) async -> Bool { false }

    func deserialize(_ data: Data) async throws -> MediaImage {
        // Replace this with the custom format's actual image conversion.
        throw ImageDeserializationError.invalidData
    }
}

let loader = DefaultMediaImageLoader(
    downloader: DefaultImageDataDownloader(),
    decoders: [CustomImageDecoder(), ImageIOImageDecoder(), AVFoundationVideoFrameDecoder()],
    processor: ResizeImageProcessor(),
    cache: InMemoryImageCache()
)
```

Implement `MediaAsset` to define a stable `uniqueKey`, an optional fallback image, optional media metadata, and a way to load the source data.

## License

Vulp is available under the [MIT License](LICENSE).
