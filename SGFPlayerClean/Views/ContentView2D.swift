// MARK: - File: ContentView2D.swift (v3.360)
import SwiftUI

struct ContentView2D: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                mainBoardArea
                Divider().background(Color.white.opacity(0.1))
                PlaybackControlsView()
            }
            Divider().background(Color.white.opacity(0.1))
            RightPanelView()
                .frame(width: 320)
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }
    
    private var mainBoardArea: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let boardVM = app.boardVM {
                BoardView2D(boardVM: boardVM, layoutVM: app.layoutVM)
                    .padding(20)
            }
        }
    }
}

struct PlaybackControlsView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        HStack(spacing: 20) {
            Button(action: { app.boardVM?.stepBackward() }) { Image(systemName: "backward.fill").font(.title2) }.buttonStyle(.plain)
            Button(action: { if app.player.isPlaying { app.boardVM?.pause() } else { app.boardVM?.play() } }) { Image(systemName: app.player.isPlaying ? "pause.fill" : "play.fill").font(.title) }.buttonStyle(.plain)
            Button(action: { app.boardVM?.stepForward() }) { Image(systemName: "forward.fill").font(.title2) }.buttonStyle(.plain)
            Spacer()
            Text("Move: \(app.boardVM?.currentMoveIndex ?? 0) / \(app.boardVM?.totalMoves ?? 0)").font(.caption.monospacedDigit()).foregroundColor(.gray)
        }.padding().foregroundColor(.white).background(Color.black.opacity(0.3))
    }
}
