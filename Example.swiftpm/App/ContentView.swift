import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import VulpUI

struct ContentView: View {
    @State private var services = DemoServices()
    @State private var isConfirmingCacheClear = false
    @State private var didClearCache = false

    var body: some View {
        NavigationStack {
            List {
                Section("表示形式") {
                    NavigationLink("WebP / APNG / GIF / PNG / JPEG") {
                        FormatsDemoView(services: services)
                    }
                    NavigationLink("アニメーション絵文字グリッド · 1,000件") {
                        EmojiGridDemoView(services: services)
                    }
                }

                Section("統合と処理") {
                    NavigationLink("SwiftUI と UIKit") {
                        FrameworksDemoView(services: services)
                    }
                    NavigationLink("サイズ別キャッシュとカスタム処理") {
                        ProcessingDemoView(services: services)
                    }
                    NavigationLink("動画サムネイル") {
                        VideoThumbnailDemoView(services: services)
                    }
                }

                Section("素材") {
                    NavigationLink("素材の出典とライセンス") {
                        AssetLicensesView()
                    }
                }

                Section {
                    Button("すべての画像キャッシュを削除", role: .destructive) {
                        isConfirmingCacheClear = true
                    }
                } footer: {
                    Text("メモリ上のデコード済み画像と、ディスク上の取得済みデータを削除します。")
                }
            }
            .navigationTitle("Vulp")
            .confirmationDialog("キャッシュを削除しますか？", isPresented: $isConfirmingCacheClear) {
                Button("削除", role: .destructive) {
                    Task {
                        await services.loader.clearCache()
                        didClearCache = true
                    }
                }
            }
            .alert("キャッシュを削除しました", isPresented: $didClearCache) {
                Button("閉じる", role: .cancel) {}
            }
        }
    }
}

struct DemoServices {
    let loader: DemoLoader
    let dataCache: DiskAssetDataCache
    private let downloader: DefaultAssetDataDownloader
    private let imageCache: InMemoryImageCache

    init() {
        let dataCache = DiskAssetDataCache(maxSizeBytes: 256 * 1024 * 1024)
        let downloader = DefaultAssetDataDownloader()
        let imageCache = InMemoryImageCache(countLimit: 240)
        self.dataCache = dataCache
        self.downloader = downloader
        self.imageCache = imageCache
        self.loader = DemoLoader(
            downloader: downloader,
            decoders: [ImageIOImageDecoder(), AVFoundationVideoFrameDecoder()],
            processor: ResizeImageProcessor(),
            cache: imageCache,
            dataCache: dataCache
        )
    }

    func loader<Processor: ImageProcessor>(processor: Processor) -> DemoLoader {
        DemoLoader(
            downloader: downloader,
            decoders: [ImageIOImageDecoder(), AVFoundationVideoFrameDecoder()],
            processor: processor,
            cache: imageCache,
            dataCache: dataCache
        )
    }
}

typealias DemoLoader = DefaultMediaImageLoader

private enum DemoAssets {
    static var gif: FileMediaAsset { asset("animation.gif") }
    static var apng: FileMediaAsset { asset("animation.apng") }
    static var webp: FileMediaAsset { asset("animation.webp") }
    static var png: FileMediaAsset { asset("sample.png") }
    static var jpeg: FileMediaAsset { asset("sample.jpeg") }
    static var video: FileMediaAsset { asset("video-thumbnail-demo.mp4") }

    static func asset(_ filename: String) -> FileMediaAsset {
        let url = Bundle.main.url(forResource: filename, withExtension: nil)!
        // Bump this revision when bundled files change so an older disk-cached
        // source with the same filename cannot replace the new sample.
        return FileMediaAsset(url: url, uniqueKey: "demo-cc-media-3-\(filename)")
    }
}

private struct FormatsDemoView: View {
    let services: DemoServices
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                FormatCard(title: "WebP · animated", asset: DemoAssets.webp, services: services)
                FormatCard(title: "APNG · animated", asset: DemoAssets.apng, services: services)
                FormatCard(title: "GIF · animated", asset: DemoAssets.gif, services: services)
                FormatCard(title: "PNG · still", asset: DemoAssets.png, services: services)
                FormatCard(title: "JPEG · still", asset: DemoAssets.jpeg, services: services)
            }
            .padding()
        }
        .navigationTitle("画像フォーマット")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FormatCard: View {
    let title: String
    let asset: any MediaAsset
    let services: DemoServices

    init(title: String, asset: any MediaAsset, services: DemoServices) {
        self.title = title
        self.asset = asset
        self.services = services
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                VulpUI.AsyncImageTimelineView(
                    asset: asset,
                    loader: services.loader,
                    targetSize: CGSize(width: 320, height: 240),
                    prefetchCount: 2,
                    content: { $0.resizable().scaledToFit() }
                ) {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(title).font(.subheadline.weight(.semibold))
        }
    }
}

private struct EmojiGridDemoView: View {
    let services: DemoServices
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)
    private let count = 1_000

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    EmojiAnimationCell(index: index, services: services)
                }
            }
            .padding(8)
        }
        .navigationTitle("小型アニメーション画像")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text("1,000件 · 表示領域内だけを生成 · 先読み1フレーム")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}

private struct EmojiAnimationCell: View {
    let index: Int
    let services: DemoServices
    private let emojis = ["🐱", "🐸", "🦊", "🐼", "🐙", "🦄", "🐳", "🐝"]

    var body: some View {
        VulpUI.AsyncImageTimelineView(
            asset: DemoAssets.gif,
            loader: services.loader,
            targetSize: CGSize(width: 36, height: 36),
            levelOfIntegrity: 0.5,
            prefetchCount: 1,
            content: { $0.resizable().scaledToFit() }
        ) {
            Text(emojis[index % emojis.count])
                .font(.system(size: 22))
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct FrameworksDemoView: View {
    let services: DemoServices
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("SwiftUI")
                    .font(.headline)
                VulpUI.AsyncImageTimelineView(
                    asset: DemoAssets.jpeg,
                    loader: services.loader,
                    targetSize: CGSize(width: 720, height: 480),
                    content: { $0.resizable().scaledToFit() }
                ) {
                    ProgressView()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("UIKit · CALayer")
                    .font(.headline)
                UIKitImageSample(asset: DemoAssets.jpeg, loader: services.loader)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .navigationTitle("SwiftUI / UIKit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UIKitImageSample: UIViewRepresentable {
    let asset: any MediaAsset
    let loader: DemoLoader

    func makeUIView(context: Context) -> AsyncImageView {
        let view = AsyncImageView()
        view.contentMode = .scaleAspectFit
        Task {
            do {
                try await view.loadImage(asset: asset, using: loader, targetSize: CGSize(width: 540, height: 360))
            } catch {
                view.image = nil
            }
        }
        return view
    }

    func updateUIView(_ uiView: AsyncImageView, context: Context) {}
}

private struct ProcessingDemoView: View {
    let services: DemoServices
    @State private var side: CGFloat = 180
    @State private var usesSepia = false
    @State private var image: CGImage?
    @State private var error: String?

    private var request: MediaImageRequest? {
        try? MediaImageRequest(
            asset: DemoAssets.jpeg,
            targetSize: CGSize(width: side * 2, height: side * 2),
            cacheIdentifier: "processing-demo-\(Int(side * 2))-\(usesSepia)"
        )
    }

    var body: some View {
        Form {
            Section("描画サイズを要求サイズへ反映") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)

                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)
                    } else if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 336)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    metricRow("表示サイズ", value: "\(Int(side)) × \(Int(side)) pt")
                    metricRow("使用画像", value: processedImageSize)
                    metricRow("キャッシュ枠", value: cacheSize)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Slider(value: $side, in: 72...320, step: 8)
                    .accessibilityLabel("画像の表示サイズ")
                Toggle("カスタム・セピア処理", isOn: $usesSepia)
            }
            Section("プロセッサ") {
                Text("ResizeImageProcessor → SepiaProcessor。処理条件はcacheIdentifierに含め、異なる結果を分けてキャッシュします。")
                    .font(.footnote)
            }
        }
        .navigationTitle("処理とキャッシュ")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request?.cacheIdentifier) {
            await loadImage()
        }
    }

    private var processedImageSize: String {
        guard let image else { return "読み込み中…" }
        return "\(image.width) × \(image.height) px"
    }

    private var cacheSize: String {
        guard let request else { return "—" }
        return "\(Int(request.targetSize.width)) × \(Int(request.targetSize.height)) px"
    }

    @ViewBuilder
    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let request else { return }
        image = nil
        error = nil
        do {
            if usesSepia {
                let processorLoader = services.loader(processor: ResizeImageProcessor() + SepiaProcessor())
                image = try await processorLoader.load(request)
            } else {
                image = try await services.loader.load(request)
            }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct SepiaProcessor: ImageProcessor {
    @concurrent
    func process<Request: MediaImageRequestProtocol>(_ image: CGImage, for request: Request) async throws -> CGImage {
        let filter = CIFilter.sepiaTone()
        filter.inputImage = CIImage(cgImage: image)
        filter.intensity = 0.85
        guard let output = filter.outputImage,
              let result = CIContext().createCGImage(output, from: output.extent)
        else { return image }
        return result
    }
}

private struct VideoThumbnailDemoView: View {
    let services: DemoServices
    @State private var image: CGImage?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                } else if isLoading {
                    ProgressView("動画を取得中…")
                } else if let error {
                    ContentUnavailableView("取得できませんでした", systemImage: "video.slash", description: Text(error))
                } else {
                    ContentUnavailableView("動画サムネイル", systemImage: "video", description: Text("動画の先頭フレームを取得します。"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            Button("サムネイルを取得") {
                Task { await loadThumbnail() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding()
        .navigationTitle("動画サムネイル")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func loadThumbnail() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let request = try MediaImageRequest(
                asset: DemoAssets.video,
                targetSize: CGSize(width: 720, height: 405)
            )
            image = try await services.loader.load(request)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AssetLicensesView: View {
    var body: some View {
        List {
            Section("アニメーション画像") {
                LicenseCredit(
                    title: "WebP · Simple Animated Clock",
                    creator: "HFWMan · CC BY-SA 4.0",
                    source: "https://commons.wikimedia.org/wiki/File:Simple_Animated_Clock.webp",
                    license: "https://creativecommons.org/licenses/by-sa/4.0/"
                )
                LicenseCredit(
                    title: "APNG · Moving shamrock face",
                    creator: "Sswonk, based on work by Sniperz11 · CC BY-SA 3.0",
                    source: "https://commons.wikimedia.org/wiki/File:Gubu_animation.png",
                    license: "https://creativecommons.org/licenses/by-sa/3.0/"
                )
                LicenseCredit(
                    title: "GIF · Bouncing ball",
                    creator: "Branko · Public domain",
                    source: "https://commons.wikimedia.org/wiki/File:Animexample.gif"
                )
            }

            Section("静止画") {
                LicenseCredit(
                    title: "PNG · Example shapes",
                    creator: "Mvolz · CC0 1.0",
                    source: "https://commons.wikimedia.org/wiki/File:Example_png.png",
                    license: "https://creativecommons.org/publicdomain/zero/1.0/"
                )
                LicenseCredit(
                    title: "JPEG · Nature Landscape",
                    creator: "Semen Perez · CC0 1.0",
                    source: "https://commons.wikimedia.org/wiki/File:Nature_Landscape_(248036121).jpeg",
                    license: "https://creativecommons.org/publicdomain/zero/1.0/"
                )
            }

            Section("動画") {
                LicenseCredit(
                    title: "Big Buck Bunny · 6-second excerpt",
                    creator: "Blender Foundation · CC BY 3.0",
                    source: "https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4.zip",
                    license: "https://creativecommons.org/licenses/by/3.0/",
                    note: "100秒地点から6秒を切り出し、幅320pxに縮小して音声なしで再エンコード。© 2008 Blender Foundation / www.bigbuckbunny.org"
                )
            }
        }
        .navigationTitle("素材のクレジット")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseCredit: View {
    let title: String
    let creator: String
    let source: String
    var license: String?
    var note: String?

    init(title: String, creator: String, source: String, license: String? = nil, note: String? = nil) {
        self.title = title
        self.creator = creator
        self.source = source
        self.license = license
        self.note = note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(creator).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("出典", destination: URL(string: source)!)
                if let license {
                    Link("ライセンス", destination: URL(string: license)!)
                }
            }
            .font(.footnote)
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
