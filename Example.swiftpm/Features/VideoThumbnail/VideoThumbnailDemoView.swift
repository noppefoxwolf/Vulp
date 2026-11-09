import VulpUI
import SwiftUI
import UIKit

struct VideoThumbnailDemoView: View {
    @State private var urlText = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4"
    @State private var thumbnail: CGImage?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        Form {
            Section("動画 URL") {
                TextField("https://example.com/video.mp4", text: $urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await loadThumbnail() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("サムネイルを読み込む")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoading)
            }

            Section("時刻 0 のフレーム") {
                Group {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFit()
                    } else if let errorMessage {
                        emptyState(
                            title: "サムネイルを読み込めません",
                            symbol: "video.slash",
                            message: errorMessage
                        )
                    } else {
                        emptyState(
                            title: "動画 URL を入力",
                            symbol: "video",
                            message: "動画の先頭フレームをサムネイルとして表示します。"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
            }

            Section("この例で使う API") {
                Text("RemoteMediaAsset と MediaImageRequest を作り、MediaImageLoader.default に渡します。動画 URL は AVFoundation が直接読み込みます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("動画サムネイル")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func emptyState(title: String, symbol: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @MainActor
    private func loadThumbnail() async {
        guard let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            errorMessage = "HTTP または HTTPS の URL を入力してください。"
            thumbnail = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let request = try MediaImageRequest(
                assetHandle: RemoteMediaAsset(url: url, mediaTypeHint: .video),
                targetSize: CGSize(width: 640, height: 360)
            )
            thumbnail = try await MediaImageLoader.default.load(request)
        } catch {
            thumbnail = nil
            errorMessage = error.localizedDescription
        }
    }
}
