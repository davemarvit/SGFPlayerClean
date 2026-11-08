//
//  SharedOverlays.swift
//  SGFPlayerClean
//
//  Created: 2025-11-28
//  Purpose: Floating UI controls (Settings, View Mode, Full Screen) shared by 2D/3D
//

import SwiftUI

/// Overlaying the board keeps its geometry fixed as passes and results appear.
struct BoardEventOverlay: View {
    @ObservedObject var boardVM: BoardViewModel
    var showsResult: Bool
    @State private var passOpacity = 0.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let pass = boardVM.passAnnouncement, !boardVM.isPreviewingVariation, !boardVM.isScrubbing {
                    Text(pass.text)
                        .font(.system(size: min(28, max(16, geometry.size.width * 0.037)), weight: .semibold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .padding(18)
                        .frame(width: min(210, geometry.size.width * 0.4), height: min(210, geometry.size.width * 0.4))
                        .background(.black.opacity(0.68), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.2)))
                        .opacity(passOpacity)
                        .accessibilityIdentifier("board-pass-announcement")
                }
                if showsResult, let result = boardVM.reviewEndResult {
                    VStack {
                        VStack(spacing: 4) {
                            Text("Final result").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                            Text(result).font(.system(size: 25, weight: .semibold))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 68).padding(.top, 70)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("review-final-result")
                        Spacer()
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .task(id: boardVM.passAnnouncement?.id) {
            passOpacity = 0
            guard let pass = boardVM.passAnnouncement,
                  Date.timeIntervalSinceReferenceDate - pass.startedAt < PassAnnouncement.duration else { return }
            withAnimation(.easeOut(duration: PassAnnouncement.fadeIn)) { passOpacity = 1 }
            do {
                try await Task.sleep(nanoseconds: UInt64((PassAnnouncement.fadeIn + PassAnnouncement.hold) * 1_000_000_000))
                try Task.checkCancellation()
                withAnimation(.easeIn(duration: PassAnnouncement.fadeOut)) { passOpacity = 0 }
            } catch { /* A newer move or a closed view cancels this announcement. */ }
        }
    }
}

struct SharedOverlays: View {
    @Binding var showSettings: Bool
    @Binding var buttonsVisible: Bool
    @ObservedObject var app: AppModel
    @ObservedObject var boardVM: BoardViewModel

    var body: some View {
        ZStack {
            // 1. Settings Overlay (Slide-Out)
            if showSettings {
                SettingsPanel(app: app, isPresented: $showSettings)
                    .zIndex(20)
            }

            // 2. Floating Buttons (Top LEFT Alignment)
            VStack {
                HStack(spacing: 12) {
                    if buttonsVisible {
                        // A. Settings Button
                        Button(action: {
                            // Slower animation for better slide feel (0.35s)
                            withAnimation(.easeInOut(duration: 0.35)) {
                                showSettings.toggle()
                            }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Settings & Load Game")

                        // B. Full Screen Toggle
                        Button(action: toggleFullScreen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Full Screen")

                        // C. View Mode Toggle
                        Button(action: {
                            withAnimation {
                                app.viewMode = app.viewMode == .view2D ? .view3D : .view2D
                            }
                        }) {
                            Text(app.viewMode == .view2D ? "3D" : "2D")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Switch View Mode")

                        // D. Return to the comfortable playing view (3D only).
                        if app.viewMode == .view3D {
                            Button(action: { app.recenter3DRequested.send() }) {
                                Image(systemName: "target")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Recenter board")
                            .accessibilityIdentifier("recenter-3d-board")
                            .help("Recenter board — return to the seated playing view")
                        }
                    }
                    
                    Spacer()
                }
                .padding(20)
                .transition(.opacity)
                
                Spacer()
            }
            
            // 3. Floating Buttons (Top RIGHT Alignment)
            VStack {
                HStack {
                    Spacer()
                    if buttonsVisible && !app.showRightPanel && !boardVM.localScoringVisible {
                        // C2. Sidebar Toggle (moved to right)
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                app.showRightPanel.toggle()
                            }
                        }) {
                            Image(systemName: "sidebar.right")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Show game information and controls")
                        .accessibilityLabel("Show game information and controls")
                        .accessibilityIdentifier("show-game-information")
                        .padding(20)
                        .transition(.opacity)
                    }
                }
                Spacer()
            }
        }
    }
    
    private func toggleFullScreen() {
        if let window = NSApp.keyWindow {
            window.toggleFullScreen(nil)
        }
    }
}
