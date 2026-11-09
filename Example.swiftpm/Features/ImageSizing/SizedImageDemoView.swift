import VulpUI
import SwiftUI

private typealias SizedExampleLoader = DefaultMediaImageLoader<
    DefaultImageDataDownloader,
    ImageIOImageDecoder,
    ResizeImageProcessor,
    InMemoryImageCache
>

struct SizedImageDemoView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var viewSize: CGFloat = 180
    @State private var usesFill = false
    @State private var loader: SizedExampleLoader

    private let dataCache: DiskImageDataCache

    init(dataCache: DiskImageDataCache) {
        self.dataCache = dataCache
        _loader = State(initialValue: SizedExampleLoader(
            downloader: DefaultImageDataDownloader(),
            decoder: ImageIOImageDecoder(),
            processor: ResizeImageProcessor(),
            cache: InMemoryImageCache(),
            dataCache: dataCache
        ))
    }

    private let asset = RemoteMediaAsset(
        url: URL(string: "https://picsum.photos/id/1025/1200/900")!,
        uniqueKey: "example-sized-image"
    )

    private var requestedPixelSize: CGSize {
        let pixels = viewSize * displayScale
        return CGSize(width: pixels, height: pixels)
    }

    private var processedPixelSize: CGSize {
        ImageSizeBucket.pixelSize(for: requestedPixelSize) ?? .zero
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("サイズを変えると、表示サイズを含む要求が更新されます。近いサイズは同じテクスチャ段階を使い、段階をまたぐと別サイズで処理・キャッシュします。")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Picker("表示方法", selection: $usesFill) {
                    Text("Fit").tag(false)
                    Text("Fill").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("表示方法")

                VulpUI.AsyncImage(
                    loader: loader,
                    request: { pixelSize, scale in
                        let pointSize = pixelSize ?? CGSize(width: viewSize, height: viewSize)
                        return try MediaImageRequest(
                            assetHandle: asset,
                            targetSize: CGSize(
                                width: pointSize.width * scale,
                                height: pointSize.height * scale
                            )
                        )
                    },
                    content: { image in
                        image.resizable().aspectRatio(contentMode: usesFill ? .fill : .fit)
                    }
                ) {
                    ProgressView("画像を読み込み中…")
                }
                .frame(width: viewSize, height: viewSize)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("表示サイズ: \(Int(viewSize)) pt")
                    Text(usesFill ? "Fill: 枠を覆って中央をクロップ" : "Fit: 全体を表示")
                    Text("要求ピクセル: \(Int(requestedPixelSize.width)) × \(Int(requestedPixelSize.height))")
                    Text("要求サイズ段階: \(Int(processedPixelSize.width)) × \(Int(processedPixelSize.height)) px")
                        .fontWeight(.semibold)

                    Slider(value: $viewSize, in: 64...600, step: 8)
                        .accessibilityLabel("画像の表示サイズ")
                }
                .font(.callout)
            }
            .padding()
        }
        .navigationTitle("サイズ別リサイズ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
