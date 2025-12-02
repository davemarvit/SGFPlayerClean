//
//  SupportingViews.swift
//  SGFPlayerClean
//
//  Created: 2025-11-19
//  Purpose: Small supporting UI components
//
//  Contains:
//  - TatamiBackground
//  - PlaybackControls
//  - GameInfoCard
//  - SettingsPanel (placeholder)
//

import SwiftUI

// MARK: - Tatami Background

/// Japanese tatami mat background texture
struct TatamiBackground: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.7, green: 0.65, blue: 0.5),
                        Color(red: 0.6, green: 0.55, blue: 0.4)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .ignoresSafeArea()
    }
}

// MARK: - Playback Controls

/// Playback controls (prev/next/play/pause)
struct PlaybackControls: View {

    @ObservedObject var boardVM: BoardViewModel

    var body: some View {
        HStack(spacing: 20) {
            // Go to start
            Button {
                boardVM.goToStart()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
            }
            .buttonStyle(PlaybackButtonStyle())

            // Previous move
            Button {
                boardVM.previousMove()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .buttonStyle(PlaybackButtonStyle())

            // Play/Pause
            Button {
                boardVM.toggleAutoPlay()
            } label: {
                Image(systemName: boardVM.isAutoPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(PlaybackButtonStyle())

            // Next move
            Button {
                boardVM.nextMove()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .buttonStyle(PlaybackButtonStyle())

            // Go to end
            Button {
                boardVM.goToEnd()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
            }
            .buttonStyle(PlaybackButtonStyle())
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
    }
}

/// Button style for playback controls
struct PlaybackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(10)
            .background(
                Circle()
                    .fill(
                        configuration.isPressed
                            ? Color.white.opacity(0.3)
                            : Color.white.opacity(0.1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Game Info Card

/// Displays game metadata and player info
struct GameInfoCard: View {

    @ObservedObject var boardVM: BoardViewModel
    var ogsVM: OGSGameViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Game title
            if let game = boardVM.currentGame {
                Text(game.title ?? "Go Game")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Divider()
                    .background(Color.white.opacity(0.3))

                // Players
                HStack {
                    VStack(alignment: .leading) {
                        Text("Black")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(game.blackPlayer ?? "Unknown")
                            .foregroundColor(.white)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("White")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(game.whitePlayer ?? "Unknown")
                            .foregroundColor(.white)
                    }
                }

                // Game info
                HStack {
                    Label("\(game.size ?? 19)x\(game.size ?? 19)", systemImage: "square.grid.3x3")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    if let handicap = game.handicap, handicap > 0 {
                        Label("H\(handicap)", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    if let komi = game.komi {
                        Label("\(komi, specifier: "%.1f")", systemImage: "k.circle")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // Move counter
                HStack {
                    Text("Move \(boardVM.currentMoveIndex)")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    // Captures
                    HStack(spacing: 15) {
                        // Black captures (white stones)
                        if boardVM.blackCapturedCount > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 12, height: 12)
                                Text("\(boardVM.blackCapturedCount)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }

                        // White captures (black stones)
                        if boardVM.whiteCapturedCount > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 12, height: 12)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                                Text("\(boardVM.whiteCapturedCount)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }

                // Result
                if let result = game.result {
                    Divider()
                        .background(Color.white.opacity(0.3))

                    Text("Result: \(result)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            } else {
                Text("No Game Loaded")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.6))
        )
    }
}

// MARK: - Settings Panel

/// Settings panel (placeholder for Phase 5)
struct SettingsPanel: View {

    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    withAnimation {
                        isOpen = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    // Placeholder settings
                    Text("Auto-play Speed")
                        .font(.headline)

                    Text("Board Size")
                        .font(.headline)

                    Text("Sound Effects")
                        .font(.headline)

                    // Add more settings in Phase 5
                }
                .padding()
            }

            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Preview

#Preview("Playback Controls") {
    ZStack {
        Color.black.ignoresSafeArea()

        PlaybackControls(
            boardVM: BoardViewModel()
        )
    }
    .frame(width: 600, height: 200)
}

#Preview("Game Info Card") {
    ZStack {
        Color.black.ignoresSafeArea()

        GameInfoCard(
            boardVM: {
                let vm = BoardViewModel()
                // Create a minimal SGFGame for preview
                var game = SGFGame()
                game.info.event = "Lee Sedol vs AlphaGo"
                game.info.playerBlack = "Lee Sedol 9p"
                game.info.playerWhite = "AlphaGo"
                game.boardSize = 19
                game.info.komi = "7.5"
                game.info.result = "W+Resign"
                game.info.date = "2016-03-09"

                vm.currentGame = SGFGameWrapper(
                    url: URL(fileURLWithPath: "/tmp/game.sgf"),
                    game: game
                )
                vm.currentMoveIndex = 102
                vm.blackCapturedCount = 5
                vm.whiteCapturedCount = 3
                return vm
            }()
        )
    }
    .frame(width: 400, height: 300)
}

#Preview("Tatami Background") {
    TatamiBackground()
        .frame(width: 800, height: 600)
}
