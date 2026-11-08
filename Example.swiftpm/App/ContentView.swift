import VulpUI
import SwiftUI

struct ContentView: View {
    @State private var dataCache = DiskImageDataCache()
    @State private var isShowingCacheClearConfirmation = false
    @State private var isShowingCacheClearedAlert = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Lorem Picsum ギャラリー") {
                    LoremPicsumView(dataCache: dataCache)
                }

                NavigationLink("ビューサイズに応じた画像処理") {
                    SizedImageDemoView(dataCache: dataCache)
                }

                NavigationLink("カスタムプロセッサ（セピア）") {
                    SepiaImageDemoView(dataCache: dataCache)
                }

                NavigationLink("動画 URL のサムネイル") {
                    VideoThumbnailDemoView()
                }
            }
            .navigationTitle("Vulp Example")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        isShowingCacheClearConfirmation = true
                    } label: {
                        Label("元データキャッシュを削除", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog(
                "元データキャッシュを削除しますか？",
                isPresented: $isShowingCacheClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    Task {
                        await dataCache.removeAllData()
                        isShowingCacheClearedAlert = true
                    }
                }
            } message: {
                Text("保存済みの画像本体を削除します。表示中の画像やメモリキャッシュには影響しません。")
            }
            .alert("元データキャッシュを削除しました", isPresented: $isShowingCacheClearedAlert) {
                Button("閉じる", role: .cancel) {}
            }
        }
    }
}
