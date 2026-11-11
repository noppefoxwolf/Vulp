import SwiftUI
import UIKit
import VulpUI

private typealias UIKitExampleLoader = DefaultMediaImageLoader<
    DefaultImageDataDownloader,
    ImageProcessorChain<ResizeImageProcessor, ImageSizeDebugProcessor>,
    InMemoryImageCache
>

struct UIKitImageDemoView: UIViewControllerRepresentable {
    let dataCache: DiskImageDataCache

    func makeUIViewController(context: Context) -> UIKitImageDemoViewController {
        UIKitImageDemoViewController(dataCache: dataCache)
    }

    func updateUIViewController(_ viewController: UIKitImageDemoViewController, context: Context) {}
}

@MainActor
final class UIKitImageDemoViewController: UIViewController {
    private var loader: UIKitExampleLoader
    private let dataCache: DiskImageDataCache
    private let imageView = VulpUI.AsyncImageView()
    private let imageContainer = UIView()
    private let contentModeControl = UISegmentedControl(items: ["Fit", "Fill"])
    private let sizeSlider = UISlider()
    private let sizeDebugSwitch = UISwitch()
    private let sizeLabel = UILabel()
    private let errorLabel = UILabel()
    private var imageWidthConstraint: NSLayoutConstraint!
    private var imageHeightConstraint: NSLayoutConstraint!

    private let asset = RemoteMediaAsset(
        url: URL(string: "https://picsum.photos/id/1025/1200/900")!,
        uniqueKey: "example-uikit-sized-image"
    )

    init(dataCache: DiskImageDataCache) {
        self.dataCache = dataCache
        loader = Self.makeLoader(showsImageSize: false, dataCache: dataCache)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureViews()
        loadImage()
    }

    private func configureViews() {
        contentModeControl.selectedSegmentIndex = 0
        contentModeControl.addTarget(self, action: #selector(contentModeChanged), for: .valueChanged)

        imageContainer.backgroundColor = .tertiarySystemFill
        imageContainer.layer.cornerRadius = 12
        imageContainer.clipsToBounds = true

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageView)

        sizeSlider.minimumValue = 96
        sizeSlider.maximumValue = 260
        sizeSlider.value = 200
        sizeSlider.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)

        sizeDebugSwitch.addTarget(self, action: #selector(sizeDebugDrawingChanged), for: .valueChanged)
        let debugLabel = UILabel()
        debugLabel.text = "画像の中心にサイズを描画"
        let debugControl = UIStackView(arrangedSubviews: [debugLabel, sizeDebugSwitch])
        debugControl.axis = .horizontal
        debugControl.alignment = .center
        debugControl.distribution = .equalSpacing

        sizeLabel.font = .preferredFont(forTextStyle: .subheadline)
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.textAlignment = .center
        updateSizeLabel()

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0

        let description = UILabel()
        description.font = .preferredFont(forTextStyle: .body)
        description.textColor = .secondaryLabel
        description.numberOfLines = 0
        description.text = "UIKit の AsyncImageView を CALayer で表示します。サイズを変えると、そのビューの bounds と display scale から画像の要求サイズを更新します。"

        let stack = UIStackView(arrangedSubviews: [
            description,
            contentModeControl,
            debugControl,
            imageContainer,
            sizeLabel,
            sizeSlider,
            errorLabel
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            imageContainer.heightAnchor.constraint(equalTo: imageContainer.widthAnchor),
            imageView.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor)
        ])

        imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: CGFloat(sizeSlider.value))
        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: CGFloat(sizeSlider.value))
        imageWidthConstraint.isActive = true
        imageHeightConstraint.isActive = true
    }

    @objc private func contentModeChanged() {
        imageView.contentMode = contentModeControl.selectedSegmentIndex == 1 ? .scaleAspectFill : .scaleAspectFit
    }

    @objc private func sizeChanged() {
        let size = CGFloat(sizeSlider.value)
        imageWidthConstraint.constant = size
        imageHeightConstraint.constant = size
        updateSizeLabel()
    }

    @objc private func sizeDebugDrawingChanged() {
        loader = Self.makeLoader(showsImageSize: sizeDebugSwitch.isOn, dataCache: dataCache)
        loadImage()
    }

    private func loadImage() {
        let showsImageSize = sizeDebugSwitch.isOn
        imageView.loadImage(using: loader, request: { [asset] pointSize, displayScale in
            let size = pointSize ?? .zero
            let request = try MediaImageRequest(
                assetHandle: asset,
                targetSize: size,
                scale: displayScale
            )
            guard showsImageSize else { return request }
            return try MediaImageRequest(
                assetHandle: asset,
                targetSize: request.targetSize,
                cacheIdentifier: "\(request.cacheIdentifier)|debug-size"
            )
        }, onCompletion: { [weak self] result in
            if case let .failure(error) = result {
                self?.errorLabel.text = "画像を読み込めませんでした: \(error.localizedDescription)"
            }
        })
    }

    private func updateSizeLabel() {
        sizeLabel.text = "画像ビュー: \(Int(sizeSlider.value)) pt四方"
    }

    private static func makeLoader(showsImageSize: Bool, dataCache: DiskImageDataCache) -> UIKitExampleLoader {
        UIKitExampleLoader(
            downloader: DefaultImageDataDownloader(),
            decoder: ImageIOImageDecoder(),
            processor: ResizeImageProcessor().then(ImageSizeDebugProcessor(isEnabled: showsImageSize)),
            cache: InMemoryImageCache(),
            dataCache: dataCache
        )
    }
}
