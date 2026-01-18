// MARK: - File: ContentView2D.swift (v8.100)
import SwiftUI

struct ContentView2D: View {
    @EnvironmentObject var app: AppModel
    private let boardAspectRatio: CGFloat = 1.0773
    private let sidebarW: CGFloat = 320
    
    private func getLayout(area: CGSize) -> (bW: CGFloat, bH: CGFloat, lidD: CGFloat, gap: CGFloat) {
        let totalWFactor: CGFloat = 1.412
        let bH = min((area.width * 0.88 / totalWFactor) * boardAspectRatio, area.height * 0.78)
        let bW = bH / boardAspectRatio
        return (bW, bH, bH / 3.0, bW / 19.0)
    }
    
    var body: some View {
        GeometryReader { window in
            // FIX: Use FULL window width for board layout (ignoring sidebar overlay)
            // This aligns with 3D behavior where the panel overlays the scene.
            let area = window.size // CGSize(width: window.size.width, height: window.size.height)
            let L = getLayout(area: area)
            let margin = L.bW * 0.065

            ZStack(alignment: .topLeading) {
                // 1. Background
                TatamiBackground(boardHeight: L.bH)
                
                // 2. Board & Lids Container (Centered in Window)
                VStack(spacing: 0) {
                    Spacer()
                    HStack(alignment: .top, spacing: L.gap) {
                         // Board
                         if let bvm = app.boardVM {
                             BoardView2D(boardVM: bvm, layoutVM: app.layoutVM, size: CGSize(width: L.bW, height: L.bH))
                                 .frame(width: L.bW, height: L.bH)
                         }
                         
                         // Lids (Captures)
                         VStack(spacing: 0) {
                             // WHITE PLAYER SIDE (TOP): Captured Black stones
                             SimpleLidView(stoneColor: .black, stoneCount: app.boardVM?.whiteCapturedCount ?? 0, stoneSize: L.lidD * 0.15, lidNumber: 1, lidSize: L.lidD)
                                 .padding(.top, margin - (L.lidD / 2))
                             Spacer()
                             // BLACK PLAYER SIDE (BOTTOM): Captured White stones
                             SimpleLidView(stoneColor: .white, stoneCount: app.boardVM?.blackCapturedCount ?? 0, stoneSize: L.lidD * 0.15, lidNumber: 2, lidSize: L.lidD)
                                 .padding(.bottom, margin - (L.lidD / 2))
                         }
                         .frame(height: L.bH).frame(width: L.lidD)
                    }
                    .frame(width: L.bW + L.gap + L.lidD)
                    
                    Spacer()
                    
                    if let bvm = app.boardVM {
                        PlaybackControlsView(boardVM: bvm).padding(EdgeInsets(top: 0, leading: 0, bottom: 25, trailing: 0))
                    }
                }
                .frame(width: window.size.width, height: window.size.height) // Full Window Frame
                
                // 3. Right Panel Overlay (Aligned Trailing)
                HStack {
                    Spacer()
                    RightPanelView()
                        .frame(width: sidebarW)
                        .background(Color.black.opacity(0.15))
                        // .ignoresSafeArea() // CAUSE OF CUTOFF: Removed to respect window title bar
                }
            }.keyboardShortcuts(boardVM: app.boardVM!, appModel: app)
        }
    }
}

struct PlaybackControlsView: View {
    @ObservedObject var boardVM: BoardViewModel
    @State private var localIdx: Double = 0
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Button(action: { boardVM.goToStart() }) { Image(systemName: "backward.end.fill") }.buttonStyle(.plain)
                Button(action: { boardVM.stepBackward() }) { Image(systemName: "backward.fill") }.buttonStyle(.plain)
                Button(action: { boardVM.toggleAutoPlay() }) { Image(systemName: boardVM.isAutoPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain)
                Button(action: { boardVM.stepForward() }) { Image(systemName: "forward.fill") }.buttonStyle(.plain)
                Button(action: { boardVM.goToEnd() }) { Image(systemName: "forward.end.fill") }.buttonStyle(.plain)
            }
            .font(.system(size: 13, weight: .bold))
            Divider().frame(height: 14).background(Color.white.opacity(0.3))
            Slider(value: $localIdx, in: 0...Double(max(1, boardVM.totalMoves)), onEditingChanged: { dragging in
                if !dragging { boardVM.seekToMove(Int(localIdx)) }
            })
            .onChange(of: localIdx) { _, val in boardVM.seekToMove(Int(val)) }
            .onChange(of: boardVM.currentMoveIndex) { _, val in localIdx = Double(val) }
            .tint(.white).frame(width: 140)
            Text("\(boardVM.currentMoveIndex)/\(boardVM.totalMoves)").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.8)).frame(width: 50)
        }.padding(.horizontal, 12).padding(.vertical, 6).background(Color.black.opacity(0.65)).cornerRadius(18).foregroundColor(.white).fixedSize()
    }
}
