// MARK: - File: ContentView2D.swift (v8.100)
import SwiftUI

struct ContentView2D: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.boardControlsWidth) private var controlsWidth
    static func getLayout(area: CGSize) -> (bW: CGFloat, bH: CGFloat, lidD: CGFloat, gap: CGFloat, bowlD: CGFloat) {
        typealias D = GoEquipmentDimensions2D
        let totalWidth = D.boardWidth + 2 * (D.columnPitch + D.bowlImageSpan)
        let scale = max(0, min(area.width * 0.92 / totalWidth, area.height * 0.85 / D.boardHeight))
        return (D.boardWidth * scale, D.boardHeight * scale, D.lidDiameter * scale,
                D.columnPitch * scale, D.bowlImageSpan * scale)
    }
    
    var body: some View {
        GeometryReader { window in
            let area = window.size
            let L = Self.getLayout(area: area)
            let margin = GoEquipmentDimensions2D.gridRect(in: CGSize(width: L.bW, height: L.bH)).minY
            // Off-board equipment deliberately keeps the 19x19 scale for 9/13 games.
            let stoneSize = GoEquipmentDimensions2D.blackStoneDiameter * L.bW / GoEquipmentDimensions2D.boardWidth

            ZStack(alignment: .topLeading) {
                // 2. Board & Lids Container (Centered in Window)
                VStack(spacing: 0) {
                    Spacer()
                    HStack(alignment: .top, spacing: L.gap) {
                         // Opponent's right-hand bowl above our left-hand capture lid.
                         VStack(spacing: 0) {
                             if let bvm = app.boardVM {
                                 PlayerSupplyBowlView(player: bvm.engine, stoneColor: .white, size: L.bowlD)
                                     .padding(.top, margin / 2 - L.bowlD * (29.0 / 512.0))
                             }
                             Spacer()
                             if let bvm = app.boardVM {
                                 PlayerCaptureLidView(player: bvm.engine, stoneColor: .white, stoneSize: stoneSize, lidNumber: 2, lidSize: L.lidD)
                                     .accessibilityIdentifier("black-player-capture-lid")
                                     .padding(.bottom, margin / 2)
                             }
                         }.frame(width: L.bowlD, height: L.bH)
                         // Board
                         if let bvm = app.boardVM {
                             BoardView2D(boardVM: bvm, layoutVM: app.layoutVM, size: CGSize(width: L.bW, height: L.bH))
                                 .frame(width: L.bW, height: L.bH)
                         }
                         
                         // Lids (Captures)
                         VStack(spacing: 0) {
                             // WHITE PLAYER SIDE (TOP): Captured Black stones
                             if let bvm = app.boardVM {
                                 PlayerCaptureLidView(player: bvm.engine, stoneColor: .black, stoneSize: stoneSize, lidNumber: 1, lidSize: L.lidD)
                                     .accessibilityIdentifier("white-player-capture-lid")
                                     .padding(.top, margin / 2)
                             }
                             
                             if !app.showsAnalysisWorkspace, let game = app.selection, let bvm = app.boardVM {
                                 HStack(alignment: .center, spacing: 12) {
                                     LocalGameMetadataView(game: game, boardVM: bvm, isOverlay: true)
                                         .scaleEffect(0.9)
                                         .fixedSize()

                                 }
                                 .frame(width: L.lidD, alignment: .leading) // Forces overflow exclusively to the right
                                 .padding(.top, 12)
                                 .frame(height: 80)
                             }
                             
                             Spacer()
                             if let bvm = app.boardVM {
                                 PlayerSupplyBowlView(player: bvm.engine, stoneColor: .black, size: L.bowlD)
                                     .padding(.bottom, margin / 2 - L.bowlD * (45.0 / 512.0))
                             }
                         }
                         .frame(width: L.bowlD, height: L.bH)
                    }
                    .frame(width: L.bW + 2 * (L.gap + L.bowlD))
                    
                    Spacer()
                    
                    if let bvm = app.boardVM {
                        PlaybackControlsView(boardVM: bvm).padding(EdgeInsets(top: 0, leading: 0, bottom: 25, trailing: 0))
                            .frame(width: controlsWidth ?? area.width)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: window.size.width, height: window.size.height) // Full Window Frame

            }.keyboardShortcuts(boardVM: app.boardVM!, appModel: app)
        }
    }
}

struct PlaybackControlsView: View {
    @ObservedObject private var navigationAI = KataGoEngine.shared
    @EnvironmentObject var app: AppModel
    @ObservedObject var boardVM: BoardViewModel
    @State private var localIdx: Double = 0
    private var playerSummary: String {
        func player(_ name: String?, _ rank: String?, fallback: String) -> String {
            let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rank = rank?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name?.isEmpty == false ? name! : fallback)
                + (rank?.isEmpty == false ? " " + rank! : "")
        }
        if app.mode.usesOGS && boardVM.isOnlineContext {
            return "● " + player(app.ogsClient.blackPlayerName, app.ogsClient.blackPlayerRank.map(ChallengeHelpers.formatRank), fallback: "Black")
                + " · ○ " + player(app.ogsClient.whitePlayerName, app.ogsClient.whitePlayerRank.map(ChallengeHelpers.formatRank), fallback: "White")
        }
        let info = boardVM.reviewTree?.baseGame.info ?? app.selection?.game.info
        return "● " + player(info?.playerBlack, info?.blackRank, fallback: "Black")
            + " · ○ " + player(info?.playerWhite, info?.whiteRank, fallback: "White")
    }
    private var boardStatus: String? {
        boardVM.variationFrame?.caption ?? boardVM.variationStatus ?? boardVM.moveError
            ?? (boardVM.koPoint != nil ? "Ko: immediate recapture is not allowed" : nil)
            ?? boardVM.playbackPassStatus
            ?? (boardVM.territoryIsEstimate ? "Territory overlay is an estimate; OGS supplies the final score." : nil)
            ?? (app.viewMode == .view3D ? nil : playerSummary)
    }
    var body: some View {
        VStack(spacing: 5) {
            // The 3D viewport is fitted above these controls. Keep the status
            // row's height even when empty so passes and hover captions cannot move the board.
            Text(boardStatus ?? " ")
                .font(.caption).foregroundStyle(boardVM.moveError == nil && !boardVM.territoryIsEstimate ? Color.white : Color.orange)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.black.opacity(0.65), in: Capsule())
                .help(boardVM.territoryIsEstimate ? "Territory overlay is an estimate; OGS supplies the final score." : boardVM.ruleSummary)
                .lineLimit(1).truncationMode(.middle)
                .accessibilityIdentifier("game-player-status")
                .opacity(boardStatus == nil ? 0 : 1)
                .allowsHitTesting(boardStatus != nil)
                .accessibilityHidden(boardStatus == nil)
        HStack(spacing: 12) {
            if app.mode == .localPlay && !boardVM.isOnlineContext {
                Button("Pass") { boardVM.passLocally() }
                    .buttonStyle(.plain)
                    .disabled(boardVM.localPassUnavailableReason != nil)
                    .opacity(boardVM.localPassUnavailableReason == nil ? 1 : 0.4)
                    .help(boardVM.localPassUnavailableReason ?? "Pass the turn without placing a stone")
                    .accessibilityIdentifier("local-pass-button")
                Divider().frame(height: 14).background(Color.white.opacity(0.3))
            }
            HStack(spacing: 6) {
                if app.isAIAvailable {
                    Button(action: { boardVM.seekPrevMistake() }) { 
                        Image(systemName: "arrowtriangle.backward.fill")
                    }.foregroundColor(.red).buttonStyle(.plain)
                    .disabled(boardVM.previousMistakeMove == nil)
                    .help("Previous matching mistake")
                    Divider().frame(height: 12).background(Color.white.opacity(0.3))
                }
                Button(action: { boardVM.goToStart() }) { Image(systemName: "backward.end.fill") }.buttonStyle(.plain)
                Button(action: {
                    boardVM.navigatePlayback(direction: -1, tenMoves: NSEvent.modifierFlags.contains(.shift),
                                             variation: NSEvent.modifierFlags.contains(.control))
                }) { Image(systemName: "backward.fill") }.buttonStyle(.plain)
                    .help("Previous move (Shift-click: 10 moves; Control-click: previous variation)")
                Button(action: { boardVM.toggleAutoPlay() }) { Image(systemName: boardVM.isAutoPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain)
                Button(action: {
                    boardVM.navigatePlayback(direction: 1, tenMoves: NSEvent.modifierFlags.contains(.shift),
                                             variation: NSEvent.modifierFlags.contains(.control))
                }) { Image(systemName: "forward.fill") }.buttonStyle(.plain)
                    .help("Next move (Shift-click: 10 moves; Control-click: next variation)")
                Button(action: { boardVM.goToEnd() }) { Image(systemName: "forward.end.fill") }.buttonStyle(.plain)
                if app.isAIAvailable {
                    Divider().frame(height: 12).background(Color.white.opacity(0.3))
                    Button(action: { boardVM.seekNextMistake() }) { Image(systemName: "arrowtriangle.forward.fill") }.foregroundColor(.red).buttonStyle(.plain)
                        .disabled(boardVM.nextMistakeMove == nil)
                        .help("Next matching mistake")
                }
            }
            .font(.system(size: 13, weight: .bold))
            Divider().frame(height: 14).background(Color.white.opacity(0.3))
            Slider(value: Binding(get: { localIdx }, set: { value in
                localIdx = value
                boardVM.scrub(to: Int(value))
            }), in: 0...Double(max(1, boardVM.totalMoves)), onEditingChanged: { dragging in
                if dragging { boardVM.beginScrubbing() }
                else { boardVM.endScrubbing(at: Int(localIdx)) }
            })
            .onAppear { localIdx = Double(boardVM.currentMoveIndex) }
            .onChange(of: boardVM.currentMoveIndex) { _, val in
                if !boardVM.isScrubbing { localIdx = Double(val) }
            }
            .onChange(of: boardVM.isScrubbing) { _, dragging in
                if !dragging { localIdx = Double(boardVM.currentMoveIndex) }
            }
            .onDisappear { boardVM.cancelScrubbing() }
            .accessibilityIdentifier("playback-move-slider")
            .tint(.white).frame(width: 140)
            Text("\(boardVM.currentMoveIndex)/\(boardVM.totalMoves)").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.8)).frame(width: 50)
        }.padding(.horizontal, 12).padding(.vertical, 6).background(Color(white: 0.12)).cornerRadius(18).foregroundColor(.white).fixedSize()
        }
    }
}
