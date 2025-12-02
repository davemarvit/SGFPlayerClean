//
//  ContentView3D.swift
//  SGFPlayerClean
//
//  Fixed: 3D View using Unified RightPanel
//

import SwiftUI
import SceneKit

struct ContentView3D: View {

    // MARK: - Dependencies
    @ObservedObject var app: AppModel
    @ObservedObject var boardVM: BoardViewModel
    @StateObject private var sceneManager: SceneManager3D
    @ObservedObject private var settings = AppSettings.shared

    // MARK: - Camera State
    @State private var cameraPanX: CGFloat = 4.0
    @State private var cameraPanY: CGFloat = -4.48
    @State private var cameraDistance: CGFloat = 25.0
    @State private var currentRotationX: Float = -0.7
    @State private var currentRotationY: Float = 0.0
    @State private var isUserInteracting = false

    // MARK: - UI State
    @State private var showSettings = false
    @State private var buttonsVisible = true
    @State private var fadeTimer: Timer?

    // MARK: - Initialization
    init(app: AppModel) {
        self.app = app
        self.boardVM = app.boardVM!
        
        _sceneManager = StateObject(wrappedValue: {
            let manager = SceneManager3D()
            manager.settings = AppSettings.shared
            manager.boardVM = app.boardVM!
            return manager
        }())
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            // LAYER 1: 3D Scene
            sceneView.edgesIgnoringSafeArea(.all)

            // LAYER 2: UI Layout
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    
                    // --- Left Panel: 70% ---
                    ZStack {
                        CameraControlHandler(
                            rotationX: $currentRotationX,
                            rotationY: $currentRotationY,
                            distance: $cameraDistance,
                            panX: $cameraPanX,
                            panY: $cameraPanY,
                            sceneManager: sceneManager
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { _ in isUserInteracting = true }
                                .onEnded { _ in isUserInteracting = false }
                        )

                        SharedOverlays(
                            showSettings: $showSettings,
                            buttonsVisible: $buttonsVisible,
                            app: app
                        )

                        VStack {
                            Spacer()
                            PlaybackControls(boardVM: boardVM)
                                .padding(.bottom, 40)
                        }

                        VStack {
                            Spacer()
                            HStack {
                                Text("v1.0.45-CLEAN (3D)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.leading, 30)
                                    .padding(.bottom, 15)
                                Spacer()
                            }
                        }
                    }
                    .frame(width: geometry.size.width * 0.7)
                    .background(Color.clear)

                    // --- Right Panel: 30% ---
                    // Using Unified RightPanel
                    RightPanelView(app: app, boardVM: boardVM)
                        .frame(width: geometry.size.width * 0.3)
                        .background(Color.clear)
                }
                .onChange(of: geometry.size) { _, newSize in adjustCameraForSize(newSize) }
                .onAppear { adjustCameraForSize(geometry.size) }
            }
        }
        .onAppear {
            setupScene()
            resetFadeTimer()
            if let game = app.selection {
                if boardVM.currentGame?.id != game.id {
                    boardVM.loadGame(game)
                }
                updateScene()
            }
        }
        .onDisappear {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
        .onContinuousHover { phase in handleMouseMove(phase) }
        .keyboardShortcuts(boardVM: boardVM)
        .onChange(of: app.selection) { _, newValue in
            if let game = newValue {
                if boardVM.currentGame?.id != game.id {
                   boardVM.loadGame(game)
                   updateScene()
                }
            }
        }
        // State Observers
        .onChange(of: boardVM.currentMoveIndex) { _, _ in updateScene() }
        .onChange(of: boardVM.blackCapturedCount) { _, _ in updateCapturedStones() }
        .onChange(of: boardVM.whiteCapturedCount) { _, _ in updateCapturedStones() }
        .onChange(of: settings.showLastMoveCircle) { _, _ in updateScene() }
        .onChange(of: settings.showLastMoveDot) { _, _ in updateScene() }
        .onChange(of: settings.showBoardGlow) { _, _ in updateScene() }
        .onChange(of: settings.showEnhancedGlow) { _, _ in updateScene() }
        .onChange(of: settings.showMoveNumbers) { _, _ in updateScene() }
        .onChange(of: settings.debugMoveNumberOffsetX) { _, _ in updateScene() }
        .onChange(of: settings.debugMoveNumberOffsetZ) { _, _ in updateScene() }
    }

    // MARK: - Logic
    private func adjustCameraForSize(_ size: CGSize) {
        guard !isUserInteracting, size.height > 0 else { return }
        
        let availableWidth = size.width * 0.7
        let availableHeight = size.height
        let panelAspect = availableWidth / availableHeight
        
        let targetBoardAspect: CGFloat = 1.1
        let baseDistance: CGFloat = 25.0
        
        var distance: CGFloat = baseDistance
        
        if panelAspect < targetBoardAspect {
            let squeezeFactor = targetBoardAspect / panelAspect
            distance = baseDistance * squeezeFactor
        }

        withAnimation(.easeOut(duration: 0.2)) {
            cameraDistance = distance
        }
        
        sceneManager.updateCameraPosition(distance: cameraDistance, rotationX: currentRotationX, rotationY: currentRotationY, panX: cameraPanX, panY: cameraPanY)
    }

    private var sceneView: some View {
        SceneView(scene: sceneManager.scene, pointOfView: sceneManager.cameraNode, options: [])
    }

    private func setupScene() {
        sceneManager.updateCameraPosition(distance: cameraDistance, rotationX: currentRotationX, rotationY: currentRotationY, panX: cameraPanX, panY: cameraPanY)
        updateScene()
    }

    private func updateScene() {
        let lastMove = boardVM.lastMovePosition.map { (x: $0.col, y: $0.row) }
        sceneManager.updateStones(from: app.player.board, lastMove: lastMove)
        updateCapturedStones()
    }

    private func updateCapturedStones() {
        sceneManager.updateCapturedStones(blackCaptured: boardVM.blackCapturedCount, whiteCaptured: boardVM.whiteCapturedCount)
    }

    private func handleMouseMove(_ phase: HoverPhase) {
        if case .active = phase, !buttonsVisible {
            withAnimation(.easeIn(duration: 0.2)) { buttonsVisible = true }
        }
        resetFadeTimer()
    }

    private func resetFadeTimer() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.5)) { buttonsVisible = false }
        }
    }
}
