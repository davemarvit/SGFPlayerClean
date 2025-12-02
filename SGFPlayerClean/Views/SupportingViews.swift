//
//  SupportingViews.swift
//  SGFPlayerClean
//
//  Created: 2025-11-28
//  Purpose: Shared UI components used across 2D and 3D views
//

import SwiftUI

// MARK: - Shared Visual Style
struct FrostedGlass: ViewModifier {
    @ObservedObject var settings = AppSettings.shared
    
    // Tint Color: Darker, Bluer version of Tatami
    let tintColor = Color(red: 0.05, green: 0.2, blue: 0.15)
    
    func body(content: Content) -> some View {
        content
            // 1. The Blur Effect (Diffusiveness)
            // We assume .ultraThinMaterial has a fixed radius.
            // By fading it out (opacity < 1.0), we blend the sharp background
            // with the blurred background, simulating a "lower radius" blur.
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(settings.panelDiffusiveness) // 0.0 = Sharp, 1.0 = Frosted
            )
            // 2. The Color Tint (Opacity)
            .background(tintColor.opacity(settings.panelOpacity))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}

extension View {
    func frostedGlassStyle() -> some View {
        modifier(FrostedGlass())
    }
}

// MARK: - GameInfoCard
struct GameInfoCard: View {
    @ObservedObject var boardVM: BoardViewModel
    let ogsVM: OGSGameViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Game Info")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                if let phase = ogsVM?.gamePhase, phase != "none" {
                    Text(phase.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(4)
                }
            }

            Divider().background(Color.white.opacity(0.2))
            
            // Metadata
            if let game = boardVM.currentGame?.game {
                GameMetadataView(game: game)
                Divider().background(Color.white.opacity(0.2))
            }

            // Stats
            StatRow(label: "Move", icon: "arrow.right.circle", value: "\(boardVM.currentMoveIndex)", isMonospaced: true)
            StatRow(label: "Black Captures", icon: "circle.fill", value: "\(boardVM.blackCapturedCount)")
            StatRow(label: "White Captures", icon: "circle", value: "\(boardVM.whiteCapturedCount)")
        }
        .padding(12)
        .frostedGlassStyle() // Applied shared style
    }
}

// Helper to display Player Names, Ranks, Result, and Date
struct GameMetadataView: View {
    let game: SGFGame
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Black Player
            HStack {
                Text("Black:").foregroundColor(.gray)
                Text(game.info.playerBlack ?? "Unknown").bold()
                if let rank = game.info.blackRank {
                    Text("(\(rank))").font(.caption).foregroundColor(.white.opacity(0.7))
                }
            }
            .font(.caption).foregroundColor(.white)
            
            // White Player
            HStack {
                Text("White:").foregroundColor(.gray)
                Text(game.info.playerWhite ?? "Unknown").bold()
                if let rank = game.info.whiteRank {
                    Text("(\(rank))").font(.caption).foregroundColor(.white.opacity(0.7))
                }
            }
            .font(.caption).foregroundColor(.white)
            
            // Result & Date
            HStack {
                Text(game.info.date ?? "").font(.caption2).foregroundColor(.gray)
                Spacer()
                Text(game.info.result ?? "").font(.caption2).bold().foregroundColor(.yellow)
            }
            .padding(.top, 2)
        }
    }
}

struct StatRow: View {
    let label: String
    let icon: String
    let value: String
    var isMonospaced: Bool = false
    
    var body: some View {
        HStack {
            Label(label, systemImage: icon).font(.caption)
            Spacer()
            Text(value)
                .font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
        }
        .foregroundColor(.white.opacity(0.9))
    }
}

// MARK: - PlaybackControls
struct PlaybackControls: View {
    @ObservedObject var boardVM: BoardViewModel

    var body: some View {
        HStack(spacing: 12) {
            
            // 1. Buttons
            HStack(spacing: 4) {
                controlButton("backward.end.fill", help: "Start") { boardVM.goToStart() }
                controlButton("backward.fill", help: "-1 Move") { boardVM.previousMove() }
                
                Button(action: { boardVM.toggleAutoPlay() }) {
                    Image(systemName: boardVM.isAutoPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Play/Pause")
                
                controlButton("forward.fill", help: "+1 Move") { boardVM.nextMove() }
                controlButton("forward.end.fill", help: "End") { boardVM.goToEnd() }
            }
            
            Divider().frame(height: 20).background(Color.white.opacity(0.3))
            
            // 2. Slider
            Slider(value: Binding(
                get: { Double(boardVM.currentMoveIndex) },
                set: { boardVM.seekToMove(Int($0)) }
            ), in: 0...Double(boardVM.totalMoves))
            .tint(.white)
            .frame(width: 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frostedGlassStyle() // Applied shared style
    }
    
    private func controlButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        VStack {
            ProgressView().scaleEffect(1.5).padding()
            Text("Loading Games...").font(.headline).foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
    }
}

// MARK: - Tatami Background
struct TatamiBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.90, green: 0.85, blue: 0.72)
            Image("tatami")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
        }
        .ignoresSafeArea()
    }
}
