//
//  SharedOverlays.swift
//  SGFPlayerClean
//
//  Created: 2025-11-28
//  Purpose: Floating UI controls (Settings, View Mode, Full Screen) shared by 2D/3D
//

import SwiftUI

struct SharedOverlays: View {
    @Binding var showSettings: Bool
    @Binding var buttonsVisible: Bool
    @ObservedObject var app: AppModel

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

                        // B. View Mode Toggle
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
                        
                        // C. Full Screen Toggle
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
                    }
                    
                    Spacer()
                }
                .padding(20)
                .transition(.opacity)
                
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
