import SwiftUI
import UIKit
import VulpUI

struct UIKitAsyncImageGridView: View {
    @State private var seed = UUID().uuidString

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]
    private let imageCount = 72

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("UIKit のレイヤーベース AsyncImageView を、各セルの表示サイズに合わせて読み込みます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<imageCount, id: \.self) { index in
                        UIKitAsyncImageGridCell(url: imageURL(for: index))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("UIKit AsyncImage グリッド")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    seed = UUID().uuidString
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func imageURL(for index: Int) -> URL {
        URL(string: "https://picsum.photos/seed/vulp-uikit-\(seed)-\(index)/480/480.jpg")!
    }
}

private struct UIKitAsyncImageGridCell: View {
    @State private var didFail = false

    let url: URL

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                VulpUI.AsyncImage(
                    url: url,
                    contentMode: .scaleAspectFill,
                    onCompletion: { result in
                        switch result {
                        case .success:
                            break
                        case .failure:
                            didFail = true
                        }
                    }
                )
            }
            .overlay {
                if didFail {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onChange(of: url) { _, _ in
                didFail = false
            }
    }
}
