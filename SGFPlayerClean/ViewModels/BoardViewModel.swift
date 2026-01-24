// ========================================================
// FILE: ./ViewModels/BoardViewModel.swift
// VERSION: v8.214 (Clean Rewrite)
// ========================================================
import Foundation
import SwiftUI
import Combine

class BoardViewModel: ObservableObject {
    @Published var isOnlineContext: Bool = false
    @Published var lastMovePosition: BoardPosition?
    @Published var currentMoveIndex: Int = 0
    @Published var stonesToRender: [RenderStone] = []
    @Published var ghostPosition: BoardPosition?
    @Published var ghostColor: Stone?
    @Published var blackCapturedCount: Int = 0
    @Published var whiteCapturedCount: Int = 0
    @Published var isAutoPlaying: Bool = false
    @Published var totalMoves: Int = 0
    @Published var territoryPoints: [BoardPosition: Stone] = [:]
    
    let onRequestUpdate3D = PassthroughSubject<Void, Never>()
    var engine: SGFPlayer
    var ogsClient: OGSClient
    var onPlaySound: ((AppModel.SoundType) -> Void)?
    
    private var jitterEngine: StoneJitter
    private var isSyncing = false
    private var lastObservedMoveIndex: Int = 0
    private var cancellables = Set<AnyCancellable>()
    
    init(player: SGFPlayer, ogsClient: OGSClient) {
        self.engine = player
        self.ogsClient = ogsClient
        self.jitterEngine = StoneJitter(boardSize: player.board.size, eccentricity: CGFloat(AppSettings.shared.jitterMultiplier))
        
        player.moveProcessed.receive(on: RunLoop.main).sink { [weak self] in self?.syncState() }.store(in: &cancellables)
        
        AppSettings.shared.$jitterMultiplier
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] val in
                self?.jitterEngine.setEccentricity(CGFloat(val))
                self?.syncState()
            }
            .store(in: &cancellables)
            
        // OGS Scoring Observers
        ogsClient.$removedStones.receive(on: RunLoop.main).sink { [weak self] _ in self?.syncState() }.store(in: &cancellables)
        ogsClient.$phase.receive(on: RunLoop.main).sink { [weak self] _ in self?.syncState() }.store(in: &cancellables)
        
        // FIX: Sync Captures from OGSClient
        ogsClient.$blackCaptures.receive(on: RunLoop.main).sink { [weak self] val in
            if self?.isOnlineContext == true { self?.blackCapturedCount = val }
        }.store(in: &cancellables)
        
        ogsClient.$whiteCaptures.receive(on: RunLoop.main).sink { [weak self] val in
             if self?.isOnlineContext == true { self?.whiteCapturedCount = val }
        }.store(in: &cancellables)
    }
    
    var boardSize: Int { self.engine.board.size }
    
    func resetToEmpty() {
        self.engine.clear()
        self.stonesToRender = []
        self.lastMovePosition = nil
        self.isOnlineContext = false
        self.lastObservedMoveIndex = 0
        self.syncState()
    }
    
    func loadGame(_ wrapper: SGFGameWrapper) { 
        self.isOnlineContext = false
        self.engine.load(game: wrapper.game)
        self.jitterEngine = StoneJitter(boardSize: self.boardSize)
        self.lastObservedMoveIndex = self.engine.currentIndex
        self.syncState()
    }
    
    func goToStart() { engine.seek(to: 0) }
    func goToEnd() { engine.seek(to: engine.maxIndex) }
    func stepForward() { engine.stepForward() }
    func stepBackward() { engine.stepBackward() }
    func stepForwardTen() { for _ in 0..<10 { engine.stepForward() } }
    func stepBackwardTen() { for _ in 0..<10 { engine.stepBackward() } }
    func toggleAutoPlay() { if engine.isPlaying { engine.pause() } else { engine.play() } }
    func seekToMove(_ index: Int) { engine.seek(to: index) }
    func stopAutoPlay() { engine.pause() }
    func startAutoPlay() { engine.play() }
    
    func handleRemoteMove(x: Int, y: Int, color: Stone) {
        self.engine.playMoveOptimistically(color: color, x: x, y: y)
    }
    
    func handleRemotePass(color: Stone) {
        SoundManager.shared.play("pass")
        self.engine.playMoveOptimistically(color: color, x: -1, y: -1)
    }
    
    func initializeOnlineGame(width: Int, height: Int, initialStones: [BoardPosition: Stone], nextPlayer: Stone, stateVersion: Int) {
        self.stonesToRender = []
        self.objectWillChange.send()
        self.isOnlineContext = true
        self.jitterEngine = StoneJitter(boardSize: width)
        self.engine.clear()
        NSLog("[OGS-BVM] 🧹 Engine Cleared. Loading Online Game (Version: \(stateVersion))")
        self.engine.loadOnline(size: width, setup: initialStones, nextPlayer: nextPlayer, stateVersion: stateVersion)
        self.isSyncing = false
        Task { @MainActor in self.syncState() }
    }
    
    func placeStone(at pos: BoardPosition) {
        let p = ogsClient.phase ?? "unknown"
        let isOnline = isOnlineContext
        let myColor = ogsClient.playerColor ?? .white
        let turn = self.engine.turn
        
        NSLog("[Input] Click at \(pos). Online: \(isOnline). Phase: \(p). Turn: \(turn). MyColor: \(myColor).")
        
        if isOnline {
             let resolvedColor = ogsClient.playerColor ?? .white
             // NSLog("[OGS-DEBUG-COLOR] Resolved: \(resolvedColor). MyID: \(ogsClient.playerID ?? -1).")
        }
        
        // 1. Dead Stone Removal
        if ogsClient.isGameFinished || p == "stone removal" || p == "finished" {
            self.ghostPosition = nil
            if p == "stone removal" {
                 if let gameID = ogsClient.activeGameID {
                    var currentRemoved = ogsClient.removedStones
                    let group = self.engine.getGroup(at: pos)
                    // ... (rest of dead stone logic)
                    let isClickedStoneDead = currentRemoved.contains(pos)
                    let newRemovedState = !isClickedStoneDead
                    if newRemovedState { currentRemoved.formUnion(group) } else { currentRemoved.subtract(group) }
                    let coords = group.map { SGFCoordinates.toSGF(x: $0.col, y: $0.row) }.joined()
                    ogsClient.sendRemovedStones(gameID: gameID, stones: coords, removed: newRemovedState)
                }
            } else {
                NSLog("[Input] Ignored: Game Finished.")
            }
            return
        }
        
        // 2. Play Phase
        if isOnlineContext {
            // FIX: Trust Server Authority for Turn STRICTLY
            // The local engine might be out of sync (e.g. misses 'undo pass'), but if Server says it's my turn, let me play.
            let serverSaysMyTurn = (ogsClient.playerID != nil && ogsClient.playerID == ogsClient.currentPlayerID)
            
            // If online, we MUST wait for server entitlement. Engine prediction is irrelevant for permission.
            guard serverSaysMyTurn else {
                NSLog("[Input] Ignored: Not My Turn (Server Authority). MyID: \(ogsClient.playerID ?? -1). Current: \(ogsClient.currentPlayerID ?? -1).")
                return
            }
            
            if pos.row < self.engine.board.grid.count, 
               pos.col < self.engine.board.grid[0].count,
               self.engine.board.grid[pos.row][pos.col] != nil {
                NSLog("[Input] Ignored: Spot Occupied.")
                return
            }
            
            if self.engine.isSuicide(color: myColor, x: pos.col, y: pos.row) {
                NSLog("[Input] Ignored: Suicide Move.")
                return
            }
            
            let oldB = self.engine.blackStonesCaptured
            let oldW = self.engine.whiteStonesCaptured
            
            self.ghostPosition = nil
            self.engine.playMoveOptimistically(color: myColor, x: pos.col, y: pos.row)
            
            let newB = self.engine.blackStonesCaptured
            let newW = self.engine.whiteStonesCaptured
            let captured = (newB - oldB) + (newW - oldW)
            
            if captured > 1 { onPlaySound?(.captureMultiple) }
            else if captured == 1 { onPlaySound?(.captureSingle) }
            else { onPlaySound?(.place) }
            
            self.ogsClient.sendMove(gameID: self.ogsClient.activeGameID ?? 0, x: pos.col, y: pos.row)
        } else {
             if pos.row < self.engine.board.grid.count, 
                pos.col < self.engine.board.grid[0].count,
                self.engine.board.grid[pos.row][pos.col] != nil {
                 return
             }
             if self.engine.isSuicide(color: self.engine.turn, x: pos.col, y: pos.row) { return }
             self.engine.playMoveOptimistically(color: self.engine.turn, x: pos.col, y: pos.row)
        }
    }
    
    func syncState() {
        let idx = self.engine.currentIndex
        NSLog("[OGS-UI-DEBUG] 🎨 syncState Entry. Index: \(idx). Online: \(isOnlineContext)")
        let last = self.engine.lastMove.flatMap { m -> BoardPosition? in
            if m.x < 0 || m.y < 0 { return nil }
            return BoardPosition(m.y, m.x)
        }
        let snap = self.engine.board
        
        self.jitterEngine.prepare(forMove: idx, stones: snap.stones)
        var list: [RenderStone] = []
        for (pos, col) in snap.stones {
            let off = self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: idx, stones: snap.stones)
            var rs = RenderStone(id: pos, color: col, offset: off)
            
            if isOnlineContext {
               let p = ogsClient.phase
               if (p == "stone removal" || p == "finished") {
                   if ogsClient.removedStones.contains(pos) { rs.isDead = true }
               }
            }
            list.append(rs)
        }
        let safeList = list.sorted {
            if $0.id.row != $1.id.row { return $0.id.row < $1.id.row }
            return $0.id.col < $1.id.col
        }
        
        self.stonesToRender = safeList
        
        if isOnlineContext {
           let p = ogsClient.phase
           if (p == "stone removal" || p == "finished") && self.engine.currentIndex == self.engine.maxIndex {
                let t = self.engine.calculateTerritory(deadStones: ogsClient.removedStones)

                // Debug Territory
                if !t.isEmpty {
                     let counts = t.values.reduce(into: ["Black":0, "White":0]) { $0[$1 == .black ? "Black":"White", default: 0] += 1 }
                     NSLog("[OGS-TERRITORY] 🏳️🏴 Calculated: \(counts). Dead Stones: \(ogsClient.removedStones.count)")
                }

                self.territoryPoints = t
           } else {
               self.territoryPoints = [:]
           }
        } else {
            self.territoryPoints = [:]
        }
        
        if !isOnlineContext {
             if idx == (self.lastObservedMoveIndex + 1) {
                 let oldBlack = self.blackCapturedCount
                 let oldWhite = self.whiteCapturedCount
                 let newBlack = self.engine.whiteStonesCaptured
                 let newWhite = self.engine.blackStonesCaptured
                 
                 let captured = (newBlack - oldBlack) + (newWhite - oldWhite)
                 
                 if captured > 0 { 
                     if captured > 1 { onPlaySound?(.captureMultiple) }
                     else { onPlaySound?(.captureSingle) }
                 } else { 
                     onPlaySound?(.place) 
                 }
             }
        }
        self.lastObservedMoveIndex = idx
        
        self.lastMovePosition = last
        self.currentMoveIndex = idx
        
        if isOnlineContext {
            // Use Server's authoritative capture counts
            self.blackCapturedCount = ogsClient.blackCaptures
            self.whiteCapturedCount = ogsClient.whiteCaptures
            
            // Debug Log for Critical Zero-Capture Issue
            // NSLog("[OGS-SYNC] 🔄 Sync Captures: B:\(self.blackCapturedCount) W:\(self.whiteCapturedCount) (Client: \(ogsClient.blackCaptures)/\(ogsClient.whiteCaptures))")
            self.whiteCapturedCount = ogsClient.whiteCaptures
        } else {
            // Use Local Engine's calculated counts
            self.blackCapturedCount = self.engine.whiteStonesCaptured
            self.whiteCapturedCount = self.engine.blackStonesCaptured
        }
        
        self.isAutoPlaying = self.engine.isPlaying
        self.totalMoves = self.engine.maxIndex
        self.onRequestUpdate3D.send()
        self.objectWillChange.send()
    }
    
    func updateGhostStone(at pos: BoardPosition?) {
        guard isOnlineContext && engine.turn == ogsClient.playerColor else {
            self.ghostPosition = nil
            return
        }
        
        let p = ogsClient.phase ?? "unknown"
        if p == "stone removal" || p == "scoring" {
            self.ghostPosition = nil
            return
        }
        self.ghostPosition = pos
        self.ghostColor = self.engine.turn
    }
    
    func clearGhostStone() { self.ghostPosition = nil }
    
    func getJitterOffset(forPosition pos: BoardPosition) -> CGPoint {
        return self.jitterEngine.offset(forX: pos.col, y: pos.row, moveIndex: self.currentMoveIndex, stones: self.engine.board.stones)
    }
}
