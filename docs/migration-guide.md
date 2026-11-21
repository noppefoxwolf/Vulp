# Nuke・Kingfisher から Vulp への移行

このガイドでは、Nuke の `ImagePipeline`、`NukeUI`、`NukeExtensions` と、Kingfisher 8 系の主要 API を使うコードを、Vulp の公開 API に移行します。移行元の API は利用中のバージョンも確認してください。[Nuke 公式ドキュメント](https://kean-docs.github.io/nuke/documentation/nuke/) · [Kingfisher 公式 Cheat Sheet](https://github.com/onevcat/Kingfisher/wiki/Cheat-Sheet)

[English](migration-guide.en.md)

## 1. 依存関係を追加する

Swift 6.4 以上と、iOS 18 以上または macOS 15 以上を用意します。Xcode の **File > Add Package Dependencies…** で Vulp を追加し、利用箇所に応じて以下の製品をターゲットにリンクします。[Package.swift](../Package.swift)

| 用途 | 製品と import |
| --- | --- |
| 非同期ロード、キャッシュ、画像処理 | `Vulp` |
| SwiftUI で画像とアニメーションを表示 | `Vulp_SwiftUI` |
| UIKit の画像ビュー | `Vulp_UIKit` |
| SwiftUI で UIKit ベースの画像ビューを利用 | `Vulp_SwiftUI_Vulp_UIKit` |
| AppKit の画像ビュー | `Vulp_AppKit` |

`VulpUI` は UI 製品をまとめて import するための製品です。画面ごとに切り替え、残りの呼び出し元がなくなった段階で Nuke・Kingfisher の import と依存関係を削除できます。

## 2. 表示を置き換える

### SwiftUI

Nuke の `LazyImage(url: url)` と Kingfisher の `KFImage(url)` は、次のように置き換えます。URL がオプショナルなモデルでは、呼び出し側で URL の有無を分岐してください。ビューは表示領域と環境の display scale からロードサイズを決めるので、親レイアウトで表示領域を確保します。

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

Nuke の状態クロージャや Kingfisher の `.onSuccess`・`.onFailure` で行っていた処理は、`onCompletion:` の `Result<CGImage, any Error>` に移します。失敗専用の表示が必要なら、画面の状態を更新して描画を切り替えます。`placeholder` の `ProgressView()` は待機表示として使えます。受信バイト数は渡されません。[表示 API](../Sources/Vulp_SwiftUI/AsyncImageTimelineView.swift)

### UIKit・AppKit

UIKit では Nuke の `LazyImageView` や `NukeExtensions.loadImage(with:into:)`、Kingfisher の `imageView.kf.setImage(with:)` を `Vulp_UIKit.AsyncImageView` に置き換えます。既存の `UIImageView` を使い続ける画面では、次節の方法でロードして `UIImage(cgImage:)` を代入できます。

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

既定の表示領域に合わせるモードでは、Auto Layout の実行前に `loadImage(url:)` を呼べます。ビューがウインドウに追加され、表示領域の幅と高さが正になるとロードを開始します。その後も表示領域や display scale の変化に合わせてリクエストを更新し、キャッシュキーが変わる場合に再ロードします。ビューが管理するロードの開始・完了は `AsyncImageViewDelegate` で受け取り、delegate は呼び出し側で保持します。再利用セルでは `prepareForReuse()` で `imageView.image = nil` を設定します。画像のプレースホルダーには `setPlaceholder(_:)` に `ImagePlaceholder` を渡せます。設定は次のロードにも使われるため、不要になった時点で `setPlaceholder(nil)` を呼びます。[UIKit の使用例](../README.md#uikit) · [プレースホルダーの使用例](../README.md#asynchronous-image-placeholders)

AppKit の `Vulp_AppKit.ImageView` は `CGImage?` を受け取る表示用のビューです。次節のローダーを呼び、MainActor 上で結果を `image` に代入します。既存の `NSImageView` では `NSImage(cgImage:size:)` で変換できます。既存ビューへの手動代入では、画面の離脱やセルの再利用時にロード元の Task をキャンセルし、古い結果を代入しないよう管理してください。[AppKit の表示 API](../Sources/Vulp_AppKit/ImageView.swift)

## 3. ロード、加工、キャッシュを移す

Nuke の `try await ImagePipeline.shared.image(for: url)` や Kingfisher の `KingfisherManager.shared.retrieveImage(with: url, …)` で取得していた画像は、アセットとリクエストを作って取得します。戻り値の `MediaImage` は `CGImage` です。

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

- **入力**。URL は `RemoteMediaAsset`、ローカルファイルは `FileMediaAsset`、エンコード済みのバイト列は `DataMediaAsset` を使います。Kingfisher の独自データプロバイダーに相当する取得処理は `MediaAsset.loadData(using:)` に実装できます。
- **リサイズ**。Nuke のリサイズ・サムネイル指定や Kingfisher の `DownsamplingImageProcessor` を使っていた箇所では、表示に必要なサイズを `MediaImageRequest` に渡します。ポイント指定では display scale を渡し、ピクセル指定では既定の `scale: 1` を使います。Vulp は近いサイズをバケットにまとめ、元画像の縦横比を維持します。表示上の fit・fill は UI 側で指定します。出力画像自体を切り抜く場合はカスタム処理が必要です。
- **カスタム処理**。`ImageProcessor` に処理を実装し、`DefaultMediaImageLoader` の生成時に渡します。複数の処理は `+` で合成できます。標準のデコード済みキャッシュキーはアセット ID、バケット化されたサイズ、フレーム指定で決まります。異なる加工設定でデコード済みキャッシュを共有する場合は、加工の識別子を含む `cacheIdentifier` を使い、各リクエストを区別してください。
- **キャッシュキー**。Nuke の独自 image ID や Kingfisher の `ImageResource(downloadURL:cacheKey:)` を使う場合、同一の取得元データを識別するキーを `RemoteMediaAsset(url:uniqueKey:)` に渡せます。既定値は URL の絶対文字列です。ユーザーや認証条件によって同じ URL の応答が変わる場合は、その区別もキーに含めます。
- **キャッシュとプリフェッチ**。画面間でローダーを共有します。標準構成はデコード済み画像を `LRUImageCache`、エンコード済みの取得元データを `DiskAssetDataCache` に保存します。`clearCache()` は両方を消去します。`MediaAssetPrefetcher(loader:)` は URL 単位で取得元データの先読みを開始・停止できます。独自キーのアセットはローダーの `prefetch(_:priority:)` に渡し、返された Task を保持してキャンセルします。表示側でも同じローダーとアセットキーを使います。[ローダーとプリフェッチの構成例](../README.md#prefetching-with-uicollectionview)

## 4. 互換性のない機能と対応方法

| 利用中の機能 | Vulp での挙動と移行方法 |
| --- | --- |
| Nuke・Kingfisher の既存ディスクキャッシュ | キーと保存方式が異なり、Vulp は既存エントリーを読み込みません。切り替え直後の再取得を想定してください。オフラインで必要な画像は事前に Vulp 側へ保存するか、アプリ管理のファイルから読み込みます。 |
| 加工済み画像のディスク保存、Kingfisher の `.cacheOriginalImage`・`.cacheSerializer` | 標準のディスクキャッシュは取得元データを保持します。メモリから加工済み画像が消えた後は再デコード・再加工します。加工済み画像の永続化が必要なら、独自の `ImageCache` などで実装します。 |
| Nuke のキャッシュ読み書き制御、Kingfisher の `.onlyFromCache`・`.forceRefresh`・`.cacheMemoryOnly`・リクエストごとの有効期限 | ロードごとに対応する組み込みオプションはありません。保存ポリシーはローダーやキャッシュの実装で管理します。`URLSession` の HTTP キャッシュ設定だけでは Vulp のキャッシュヒットを回避できません。 |
| Nuke のメモリ向けプリフェッチ、Kingfisher の `ImagePrefetcher` による加工済み画像の先読み | Vulp の標準プリフェッチは取得元データの保存までです。表示サイズで加工した画像も先に必要なら、同じリクエストを `load` する Task をアプリ側で管理します。 |
| 受信進捗、プログレッシブ JPEG、Nuke の中断したダウンロードの再開 | 標準の公開 API に受信進捗・途中画像の通知や再開の制御はありません。進捗や再開が必要ならアプリ側の取得処理で扱います。ダウンローダーを差し替えても、標準ビューに途中画像を配信する API は追加されません。 |
| Nuke の `URLRequest` 入力、Kingfisher のリクエスト修飾、リダイレクト制御、リトライ、代替 URL、Low Data Mode での画像差し替え | `RemoteMediaAsset` は URL を受け取り、標準ダウンローダーには `URLSession` を注入できます。リクエストごとのヘッダーや再試行・代替ソースの制御はカスタム `AssetDataDownloader`、`MediaAsset`、または呼び出し側に実装します。 |
| Nuke の実行中の優先度変更、Kingfisher の `.downloadPriority` | Vulp の `TaskPriority` はロード開始時に指定します。実行中の優先度を操作する画像タスクや、リクエスト単位で `URLSessionTask.priority` を設定する公開 API はありません。 |
| Nuke・Kingfisher の既成プロセッサー、フェード・キャッシュヒット時の遷移設定 | Vulp の標準処理はリサイズです。角丸やぼかしなどを画素に反映する場合は `ImageProcessor` を実装し、表示だけの変更や遷移は画面側で実装します。 |
| アニメーション固有の設定、NukeVideo の動画再生 | Vulp の SwiftUI・UIKit ビューは GIF・APNG・WebP のフレームを逐次ロードして再生します。`prefetchCount` と `levelOfIntegrity` を調整できますが、既存の全フレーム事前展開や繰り返し回数の設定に対応する組み込みオプションはありません。静止画だけが必要なら `.firstFrame` のリクエストを直接ロードします。動画はサムネイル抽出に対応し、再生は AVKit などで行います。 |
| 古い OS や iOS・macOS 以外をターゲットにした構成 | Vulp の対象は iOS 18 以上と macOS 15 以上です。その他のターゲットや古い OS を維持する場合は、対象ごとに既存の実装を残してください。 |

移行元の仕様は [Nuke の機能一覧と利用例](https://github.com/kean/Nuke#usage) · [Nuke のリクエスト実装](https://github.com/kean/Nuke/blob/main/Sources/Nuke/ImageRequest.swift) · [Kingfisher のオプション定義](https://github.com/onevcat/Kingfisher/blob/master/Sources/General/KingfisherOptionsInfo.swift) を参照してください。

## 5. 切り替え後に確認する

- 初回ロード、メモリキャッシュのヒット、アプリ再起動後のディスクキャッシュ利用を確認します。オフラインが要件なら、キャッシュが空の場合の画面も確認します。
- スクロール中のセル再利用、URL の切り替え、エラー時のプレースホルダー、表示サイズや display scale の変更を確認します。
- 大きい画像や動画サムネイルを使う場合、標準ダウンローダーは HTTP レスポンス本文を既定で 5 MiB まで受け取ります。上限を超える取得が必要なら `DefaultAssetDataDownloader(maximumDownloadSize:)` を設定したローダーを使い、実データで確認します。[ダウンローダーの実装](../Sources/Vulp/Loading/BuiltIn/DefaultAssetDataDownloader.swift)
