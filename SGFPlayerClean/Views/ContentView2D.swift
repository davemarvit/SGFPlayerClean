//
//  ContentView2D.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Main container for 2D board view
//

import SwiftUI
import Combine

struct ContentView2D: View {

    // MARK: - Layout Constants
    private struct LayoutConfig {
        static let topMargin: CGFloat = 40
        static let leftMargin: CGFloat = 40
        static let rightMargin: CGFloat = 120
        static let bottomMargin: CGFloat = 80 // Reduced bottom margin for thinner controls
        
        static let lidGap: CGFloat = 20
        static let lidVerticalSpacing: CGFloat = 30
    }

    @ObservedObject var app: AppModel
    @ObservedObject var boardVM: BoardViewModel
    @StateObject var layoutVM = LayoutViewModel()

    @State private var showSettings = false
    @State private var buttonsVisible = true
    @State private var fadeTimer: Timer?
    
    @State private var boardFrame: CGRect = .zero

    init(app: AppModel) {
        self.app = app
        self.boardVM = app.boardVM!
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // LAYER 1: Background
                TatamiBackground()
                
                // LAYER 2: Main Content
                contentLayer(geometry: geometry)
                
                // LAYER 3: Overlays
                SharedOverlays(showSettings: $showSettings, buttonsVisible: $buttonsVisible, app: app)
                
                // HIDDEN CONTROLS: Keyboard Shortcuts
                // This is the robust way to handle Shift+Arrow without macOS 14 errors
                ZStack {
                    Button("") { boardVM.seekToMove(max(boardVM.currentMoveIndex - 10, 0)) }
                        .keyboardShortcut(.leftArrow, modifiers: .shift)
                    
                    Button("") { boardVM.seekToMove(min(boardVM.currentMoveIndex + 10, boardVM.totalMoves)) }
                        .keyboardShortcut(.rightArrow, modifiers: .shift)
                }
                .opacity(0) // Invisible but active
            }
            .onAppear {
                if let game = app.selection {
                    if boardVM.currentGame?.id != game.id {
                        boardVM.loadGame(game)
                    }
                }
            }
        }
        .onAppear { onViewAppear() }
        .onDisappear { onViewDisappear() }
        .onContinuousHover { phase in handleMouseMove(phase) }
        .keyboardShortcuts(boardVM: boardVM)
        .onChange(of: app.selection) { _, newValue in
            if let game = newValue { boardVM.loadGame(game) }
        }
    }

    @ViewBuilder
    private func contentLayer(geometry: GeometryProxy) -> some View {
        let panelWidth = geometry.size.width * 0.7
        let panelHeight = geometry.size.height
        
        // 1. Calculate Board Rect
        let frame = calculateBoardFrame(containerWidth: panelWidth, containerHeight: panelHeight)
        
        ZStack(alignment: .topLeading) {
            
            // A. Board
            BoardView2D(boardVM: boardVM, layoutVM: layoutVM)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .onChange(of: frame) { _, newFrame in
                    layoutVM.updateBoardFrame(newFrame, boardSize: boardVM.boardSize)
                }
                .onAppear {
                    layoutVM.updateBoardFrame(frame, boardSize: boardVM.boardSize)
                }

            // B. Lids
            lidsOverlay(boardFrame: frame)
            
            // C. Controls (Centered under board)
            PlaybackControls(boardVM: boardVM)
                .position(x: frame.midX, y: frame.maxY + 40) // Closer to board
            
            // D. Version
            Text("v1.0.47")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.black.opacity(0.4))
                .position(x: panelWidth - 40, y: panelHeight - 20)
            
            // E. Right Panel
            RightPanelView(app: app, boardVM: boardVM)
                .frame(width: geometry.size.width * 0.3, height: panelHeight)
                .position(x: panelWidth + (geometry.size.width * 0.15), y: panelHeight / 2)
        }
    }

    private func lidsOverlay(boardFrame: CGRect) -> some View {
        let divisor = CGFloat(boardVM.boardSize + 1)
        let cellWidth = boardFrame.width / divisor
        let cellHeight = boardFrame.height / divisor
        
        let lidDiameter = cellHeight * 7.0
        
        let upperLidX = boardFrame.maxX + LayoutConfig.lidGap + (lidDiameter / 2)
        
        let totalLidsHeight = (lidDiameter * 2) + LayoutConfig.lidVerticalSpacing
        let startY = boardFrame.midY - (totalLidsHeight / 2) + (lidDiameter / 2)
        
        let upperLidY = startY
        let lowerLidX = upperLidX + (cellWidth * 0.5)
        let lowerLidY = upperLidY + lidDiameter + LayoutConfig.lidVerticalSpacing

        let lidStoneSize = cellWidth * 0.95

        return ZStack {
            SimpleLidView(stoneColor: .white, stoneCount: boardVM.blackCapturedCount, stoneSize: lidStoneSize, lidNumber: 1, lidSize: lidDiameter)
                .position(x: upperLidX, y: upperLidY)
            
            SimpleLidView(stoneColor: .black, stoneCount: boardVM.whiteCapturedCount, stoneSize: lidStoneSize, lidNumber: 2, lidSize: lidDiameter)
                .position(x: lowerLidX, y: lowerLidY)
        }
    }

    // MARK: - Layout Math
    private func calculateBoardFrame(containerWidth: CGFloat, containerHeight: CGFloat) -> CGRect {
        let availableW = containerWidth - LayoutConfig.leftMargin - LayoutConfig.rightMargin
        let availableH = containerHeight - LayoutConfig.topMargin - LayoutConfig.bottomMargin
        
        let boardAspect: CGFloat = 1.0 / 1.0773
        
        var w: CGFloat = 0
        var h: CGFloat = 0
        
        if availableW / availableH < boardAspect {
            w = availableW
            h = w / boardAspect
        } else {
            h = availableH
            w = h * boardAspect
        }
        
        let x = LayoutConfig.leftMargin + (availableW - w) / 2
        let y = LayoutConfig.topMargin + (availableH - h) / 2
        
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Event Handlers
    private func onViewAppear() { resetFadeTimer() }
    private func onViewDisappear() { fadeTimer?.invalidate(); fadeTimer = nil }
    private func handleMouseMove(_ phase: HoverPhase) {
        if case .active = phase, !buttonsVisible { withAnimation(.easeIn(duration: 0.2)) { buttonsVisible = true } }
        resetFadeTimer()
    }
    private func resetFadeTimer() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.5)) { buttonsVisible = false }
        }
    }
}
