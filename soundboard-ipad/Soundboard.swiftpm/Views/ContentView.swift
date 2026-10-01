import SwiftUI

struct ContentView: View {
    @StateObject private var store = SoundStore()
    @StateObject private var player = SoundPlayer()
    @StateObject private var youtube = YouTubeController()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showBrowser = false

    var body: some View {
        HStack(spacing: 0) {
            BoardView(store: store, player: player, showBrowser: $showBrowser)
                .frame(maxWidth: .infinity)
            // On a full-width iPad the browser sits beside the board, like on the Mac.
            if showBrowser && sizeClass == .regular {
                Divider()
                YouTubePanel(controller: youtube)
                    .frame(maxWidth: .infinity)
            }
        }
        // In Slide Over, narrow Split View or on iPhone it opens full screen instead.
        .fullScreenCover(isPresented: compactBrowser) {
            NavigationStack {
                YouTubePanel(controller: youtube)
                    .navigationTitle("YouTube")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showBrowser = false }
                        }
                    }
            }
        }
        .onAppear {
            youtube.onCaptured = { wav, name, source in
                _ = try store.add(data: wav, ext: "wav", name: name, source: source)
            }
        }
    }

    private var compactBrowser: Binding<Bool> {
        Binding(
            get: { showBrowser && sizeClass != .regular },
            set: { if !$0 { showBrowser = false } }
        )
    }
}
