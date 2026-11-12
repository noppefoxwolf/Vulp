import VulpUI
import SwiftUI

struct SepiaImageDemoView: View {
    @State private var intensity = 0.85
    @State private var loader: DefaultMediaImageLoader

    private let dataCache: DiskImageDataCache

    init(dataCache: DiskImageDataCache) {
        self.dataCache = dataCache
        _loader = State(initialValue: Self.makeLoader(intensity: 0.85, dataCache: dataCache))
    }

    private var request: MediaImageRequest {
        get throws {
            try MediaImageRequest(
                assetHandle: RemoteMediaAsset(
                    url: URL(string: "https://picsum.photos/id/1025/1200/900")!,
                    uniqueKey: "example-sepia-image"
                ),
                targetSize: CGSize(width: 720, height: 540),
                cacheIdentifier: "example-sepia-image|intensity:\(intensity)"
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("複数の ImageProcessor を順番につなげて、リサイズ後にセピアを適用します。スライダーで効果の強さを変更できます。")
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let request = try? request {
                    VulpUI.AsyncImageTimelineView(request: request, loader: loader, content: { image in
                        image.resizable().scaledToFit()
                    }) {
                        ProgressView("画像を読み込み中…")
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("セピアの強さ")
                        Spacer()
                        Text(intensity.formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: Binding(
                        get: { intensity },
                        set: updateIntensity
                    ), in: 0...1, step: 0.05)
                        .accessibilityLabel("セピアの強さ")
                }
                .font(.callout)

                Label("ResizeImageProcessor → SepiaImageProcessor", systemImage: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("セピア処理")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func updateIntensity(_ newIntensity: Double) {
        intensity = newIntensity
        loader = Self.makeLoader(intensity: newIntensity, dataCache: dataCache)
    }

    private static func makeLoader(intensity: Double, dataCache: DiskImageDataCache) -> DefaultMediaImageLoader {
        DefaultMediaImageLoader(
            downloader: DefaultImageDataDownloader(),
            decoder: ImageIOImageDecoder(),
            processor: ResizeImageProcessor() + SepiaImageProcessor(intensity: intensity),
            cache: InMemoryImageCache(),
            dataCache: dataCache
        )
    }
}
