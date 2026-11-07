import MediaLoaderUI
import SwiftUI

private typealias ExampleLoader = DefaultMediaImageLoader<
    DefaultImageDataDownloader,
    ImageIOImageDecoder,
    ResizeImageProcessor,
    InMemoryImageCache
>

struct LoremPicsumView: View {
    @State private var requests: [MediaImageRequest] = []
    @State private var errorMessage: String?
    @State private var loader: ExampleLoader

    private let dataCache: DiskImageDataCache

    init(dataCache: DiskImageDataCache) {
        self.dataCache = dataCache
        _loader = State(initialValue: ExampleLoader(
            downloader: DefaultImageDataDownloader(),
            decoder: ImageIOImageDecoder(),
            processor: ResizeImageProcessor(),
            cache: InMemoryImageCache(),
            dataCache: dataCache
        ))
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("アニメーションGIF")
                        .font(.headline)

                    MediaLoaderUI.AsyncImage(
                        asset: RemoteMediaAsset(
                            url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif")!,
                            uniqueKey: "example-rotating-earth-gif"
                        ),
                        loader: loader,
                        targetSize: CGSize(width: 240, height: 240),
                        levelOfIntegrity: 0.9,
                        onFailure: { _ in
                            errorMessage = "GIFを読み込めませんでした。ネットワークを確認してください。"
                        }
                    ) {
                        ProgressView("GIFを読み込み中…")
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(requests, id: \.cacheIdentifier) { request in
                        PicsumGridCell(request: request, loader: loader) { _ in
                            errorMessage = "画像を読み込めませんでした。更新して再試行してください。"
                        }
                    }
                }
            }

            if requests.isEmpty {
                ProgressView("画像を準備中…")
                    .padding(.top, 40)
            }
        }
        .padding()
        .navigationTitle("Lorem Picsum")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    makeRequests()
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
            }
        }
        .task {
            if requests.isEmpty {
                makeRequests()
            }
        }
    }

    @MainActor
    private func makeRequests() {
        let seed = UUID().uuidString

        do {
            requests = try (0..<18).map { index in
                let url = URL(string: "https://picsum.photos/seed/\(seed)-\(index)/500/500")!
                let asset = RemoteMediaAsset(url: url, uniqueKey: url.absoluteString)
                return try MediaImageRequest(
                    assetHandle: asset,
                    targetSize: CGSize(width: 500, height: 500)
                )
            }
            errorMessage = nil
        } catch {
            requests = []
            errorMessage = "画像を準備できませんでした: \(error.localizedDescription)"
        }
    }
}

private struct PicsumGridCell<Loader: MediaImageLoading>: View {
    @State private var didFail = false

    let request: MediaImageRequest
    let loader: Loader
    let onFailure: @MainActor @Sendable (any Error) -> Void

    var body: some View {
        Color.clear
        .aspectRatio(1, contentMode: .fit)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            MediaLoaderUI.AsyncImage(request: request, loader: loader, onFailure: { error in
                didFail = true
                onFailure(error)
            }) {
                if didFail {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
