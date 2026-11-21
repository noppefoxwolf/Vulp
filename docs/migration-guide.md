# Migrating from Nuke or Kingfisher to Vulp

[日本語](migration-guide.ja.md)

This guide covers Nuke's `ImagePipeline`, `NukeUI`, and `NukeExtensions`, and the main APIs in Kingfisher 8. Check your installed version for differences in the source APIs. [Nuke documentation](https://kean-docs.github.io/nuke/documentation/nuke/) · [Kingfisher Cheat Sheet](https://github.com/onevcat/Kingfisher/wiki/Cheat-Sheet)

## 1. Add the dependency

Vulp requires Swift 6.4 or later and iOS 18 or macOS 15 or later. In Xcode, choose **File > Add Package Dependencies…**, add Vulp, and link the products your target uses. [Package.swift](../Package.swift)

| Use case | Product and import |
| --- | --- |
| Async loading, caching, and image processing | `Vulp` |
| Image display and animation in SwiftUI | `Vulp_SwiftUI` |
| UIKit image view | `Vulp_UIKit` |
| UIKit-backed image view in SwiftUI | `Vulp_SwiftUI_Vulp_UIKit` |
| AppKit image view | `Vulp_AppKit` |

`VulpUI` re-exports the UI products. You can migrate one screen at a time and remove the Nuke or Kingfisher dependency once all callers have moved.

## 2. Replace the image views

### SwiftUI

Replace Nuke's `LazyImage(url: url)` or Kingfisher's `KFImage(url)` with `AsyncImageTimelineView`. If the model has an optional URL, handle the missing URL at the call site. Give the view a display area in the parent layout. It calculates the request size from its bounds and the environment's display scale.

```swift
import SwiftUI
import Vulp_SwiftUI

struct PhotoThumbnail: View {
    let url: URL

    var body: some View {
        AsyncImageTimelineView(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ProgressView()
        }
        .frame(width: 150, height: 150)
        .clipped()
    }
}
```

Move logic from Nuke's state closure or Kingfisher's `.onSuccess` and `.onFailure` handlers into `onCompletion:`, which receives a `Result<CGImage, any Error>`. Update view state to display a dedicated error UI. A `ProgressView()` placeholder can indicate that loading is underway. The view does not report byte counts. [SwiftUI view API](../Sources/Vulp_SwiftUI/AsyncImageTimelineView.swift)

### UIKit and AppKit

In UIKit, replace Nuke's `LazyImageView` or `NukeExtensions.loadImage(with:into:)`, or Kingfisher's `imageView.kf.setImage(with:)`, with `Vulp_UIKit.AsyncImageView`. To keep an existing `UIImageView`, use the loader in the next section and assign a `UIImage(cgImage:)`.

```swift
import UIKit
import Vulp_UIKit

@MainActor
func makePhotoView(url: URL) -> AsyncImageView {
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 150, height: 150))
    view.contentMode = .scaleAspectFill
    view.clipsToBounds = true
    view.loadImage(url: url)
    return view
}
```

With the default bounds-based sizing, you can call `loadImage(url:)` before Auto Layout runs. Loading starts once the view is in a window and has nonzero bounds. Later changes to the bounds or display scale update the request, and the view reloads if the cache key changes. For view-managed loads, receive start and completion events through `AsyncImageViewDelegate` and retain the delegate at the call site. Set `imageView.image = nil` in a reusable cell's `prepareForReuse()`. Pass an `ImagePlaceholder` to `setPlaceholder(_:)` to display a generated placeholder. The configuration persists across loads. Call `setPlaceholder(nil)` when you no longer need it. [UIKit examples](../README.md#uikit) · [Placeholder examples](../README.md#asynchronous-image-placeholders)

On AppKit, `Vulp_AppKit.ImageView` displays a `CGImage?`. Use the loader below and assign its result to `image` on the main actor. For an existing `NSImageView`, convert with `NSImage(cgImage:size:)`. When assigning results manually, cancel the loading task when leaving the screen or reusing the cell, and guard against assigning stale results. [AppKit view API](../Sources/Vulp_AppKit/ImageView.swift)

## 3. Migrate loading, processing, and caching

To replace Nuke's `try await ImagePipeline.shared.image(for: url)` or Kingfisher's `KingfisherManager.shared.retrieveImage(with: url, …)`, create an asset and a request. The loader returns `MediaImage`, a type alias for `CGImage`.

```swift
import CoreGraphics
import Foundation
import Vulp

func loadThumbnail(url: URL, displayScale: CGFloat) async throws -> CGImage {
    let request = try MediaImageRequest(
        asset: RemoteMediaAsset(url: url),
        targetSize: CGSize(width: 150, height: 150),
        scale: displayScale
    )
    return try await MediaImageLoader.default.load(request, priority: .userInitiated)
}
```

- **Source data.** Use `RemoteMediaAsset` for remote URLs, `FileMediaAsset` for local files, and `DataMediaAsset` for encoded bytes. Implement `MediaAsset.loadData(using:)` to migrate custom retrieval logic such as a Kingfisher data provider.
- **Resizing.** Replace Nuke resize or thumbnail settings and Kingfisher's `DownsamplingImageProcessor` with a `MediaImageRequest` sized for display. Pass the display scale for sizes in points, or use the default `scale: 1` for explicit pixel dimensions. Vulp groups nearby sizes into buckets and preserves the source aspect ratio. Set fit or fill in the view. Cropping the output bitmap requires a custom processor.
- **Custom processing.** Implement `ImageProcessor` and pass it when creating a `DefaultMediaImageLoader`. Combine processors with `+`. The default decoded-image cache key includes the asset ID, bucketed size, and frame selection. If different processing configurations share a decoded-image cache, include an identifier for the processing configuration in each custom `cacheIdentifier`.
- **Asset keys.** To migrate a custom Nuke image ID or Kingfisher `ImageResource(downloadURL:cacheKey:)`, pass a stable key to `RemoteMediaAsset(url:uniqueKey:)`. The default is the URL's absolute string. Include the relevant user or authorization context if the response for the same URL varies by context.
- **Caching and prefetching.** Share the loader across screens. The standard configuration keeps decoded images in `LRUImageCache` and encoded source data in `DiskAssetDataCache`. `clearCache()` clears both. Use `MediaAssetPrefetcher(loader:)` to start and stop source prefetches by URL. For assets with custom keys, call the loader's `prefetch(_:priority:)` and retain the returned task for cancellation. Use the same loader and asset key for display. [Loader and prefetch examples](../README.md#prefetching-with-uicollectionview)

## 4. Compatibility gaps and migration options

| Feature in the source library | Vulp behavior and migration options |
| --- | --- |
| Existing Nuke or Kingfisher disk cache | Vulp uses different keys and storage formats. Expect images to be fetched again after switching. For offline use, populate Vulp's cache before switching or load from app-managed files. |
| Processed images on disk, Kingfisher's `.cacheOriginalImage` and `.cacheSerializer` | The standard disk cache holds encoded source data. Vulp decodes and processes the source again after the processed image leaves memory. Implement a custom `ImageCache` if you need to persist processed images. |
| Nuke's cache read and write controls, Kingfisher's `.onlyFromCache`, `.forceRefresh`, `.cacheMemoryOnly`, and per-request expiration | Vulp has no built-in per-request equivalents. Implement the policy in a loader or cache. Changing the HTTP cache policy on `URLSession` alone does not bypass a Vulp cache hit. |
| Nuke memory prefetching and Kingfisher `ImagePrefetcher` for processed images | The standard prefetch stores encoded source data. To warm the decoded-image cache, manage a task that calls `load` with the same request used for display. |
| Download progress, progressive JPEG previews, and Nuke's resumable downloads | Vulp has no built-in byte progress callbacks, intermediate image events, or resume controls. If needed, manage progress and resumption in app-level networking. A custom downloader does not add a preview stream to the built-in views. |
| Nuke's `URLRequest` input and Kingfisher's request modifiers, redirect handlers, retries, alternate sources, and Low Data Mode fallback | `RemoteMediaAsset` accepts a URL, and the standard downloader accepts a `URLSession`. Implement request-specific headers, retries, and alternate-source selection in an `AssetDataDownloader`, a `MediaAsset`, or the calling code. |
| Nuke's in-flight priority changes and Kingfisher's `.downloadPriority` | Vulp accepts a `TaskPriority` when starting a load. It has no image task API for changing priority in flight or setting `URLSessionTask.priority` per request. |
| Built-in processors, fades, and transitions on cache hits | Vulp includes resizing. Implement an `ImageProcessor` for changes to pixels, such as corner masking or blur. Handle visual styling and transitions in the UI. |
| Animation-specific options and NukeVideo playback | Vulp's SwiftUI and UIKit views load and play GIF, APNG, and WebP frames incrementally. They expose `prefetchCount` and `levelOfIntegrity` but have no built-in options to decode every frame upfront or set the repeat count. For a still image, load a request with `.firstFrame` directly. Vulp extracts thumbnails from video. Use a playback framework such as AVKit for video playback. |
| Older OS versions and targets outside iOS and macOS | Vulp targets iOS 18 and macOS 15 or later. Keep the existing integration for any other targets you still support. |

See the source libraries' references for details. [Nuke usage and features](https://github.com/kean/Nuke#usage) · [Nuke request implementation](https://github.com/kean/Nuke/blob/main/Sources/Nuke/ImageRequest.swift) · [Kingfisher option definitions](https://github.com/onevcat/Kingfisher/blob/master/Sources/General/KingfisherOptionsInfo.swift)

## 5. Verify the switch

- Check first load, memory cache hits, and disk cache reuse after restarting the app. If offline use is required, also check the empty-cache behavior.
- Check cell reuse during scrolling, URL changes, error placeholders, and changes to view size or display scale.
- Try representative large images and video thumbnails. The default downloader limits HTTP response bodies to 5 MiB. Configure `DefaultAssetDataDownloader(maximumDownloadSize:)` when your app needs larger responses. [Downloader implementation](../Sources/Vulp/Loading/BuiltIn/DefaultAssetDataDownloader.swift)
