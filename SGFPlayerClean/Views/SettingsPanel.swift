//
//  SettingsPanel.swift
//  SGFPlayerClean
//
//  Created: 2025-12-01
//  Purpose: Slide-out settings drawer with visual preferences and library management
//

import SwiftUI

struct SettingsPanel: View {
    @ObservedObject var app: AppModel
    @ObservedObject var settings = AppSettings.shared
    @Binding var isPresented: Bool
    
    @State private var isMarkersExpanded = true
    
    // Logarithmic binding for Time Delay
    private var delayBinding: Binding<Double> {
        Binding<Double>(
            get: {
                let y = max(0.1, settings.moveInterval)
                return log10(y / 0.1) / log10(100.0)
            },
            set: { sliderValue in
                let y = 0.1 * pow(100.0, sliderValue)
                settings.moveInterval = y
            }
        )
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // 1. Dimmed Background
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { close() }
            
            // 2. The Sidebar Panel
            VStack(alignment: .leading, spacing: 0) {
                headerView
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        playbackSection
                        Divider().background(Color.white.opacity(0.3))
                        markersSection
                        Divider().background(Color.white.opacity(0.3))
                        librarySection
                    }
                    .padding()
                }
                
                Spacer()
                footerView
            }
            .frame(width: 350)
            .frostedGlassStyle()
            .padding(.leading, 10)
            .padding(.vertical, 10)
            .transition(.move(edge: .leading))
        }
        .zIndex(100)
    }
    
    // MARK: - Components
    
    private var headerView: some View {
        HStack {
            Text("Settings")
                .font(.title2.bold())
                .foregroundColor(.white)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.black.opacity(0.1))
    }
    
    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Playback", systemImage: "play.circle.fill")
                .font(.headline).foregroundColor(.white)
            
            // Delay Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Move Delay")
                    Spacer()
                    Text(String(format: "%.1fs", settings.moveInterval))
                        .monospacedDigit().foregroundColor(.white)
                }
                .font(.caption).foregroundColor(.white.opacity(0.8))
                Slider(value: delayBinding, in: 0.0...1.0).tint(.cyan)
            }
            
            // Jitter Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Stone Jitter")
                    Spacer()
                    Text(String(format: "%.2f", settings.jitterMultiplier))
                        .monospacedDigit().foregroundColor(.white)
                }
                .font(.caption).foregroundColor(.white.opacity(0.8))
                Slider(value: $settings.jitterMultiplier, in: 0.0...2.0, step: 0.05).tint(.cyan)
            }
            
            // Volume Sliders
            VStack(alignment: .leading, spacing: 4) {
                 HStack {
                     Text("Stone Volume") // Placement & Capture
                     Spacer()
                     Text(String(format: "%.0f%%", settings.stoneVolume * 100)).monospacedDigit().foregroundColor(.white)
                 }
                 .font(.caption).foregroundColor(.white.opacity(0.8))
                 Slider(value: $settings.stoneVolume, in: 0.0...1.0).tint(.green)

                 HStack {
                     Text("Voice Volume") // System & Speech
                     Spacer()
                     Text(String(format: "%.0f%%", settings.voiceVolume * 100)).monospacedDigit().foregroundColor(.white)
                 }
                 .font(.caption).foregroundColor(.white.opacity(0.8))
                 Slider(value: $settings.voiceVolume, in: 0.0...1.0).tint(.cyan)
            }
            
            Group {
                Toggle("Shuffle Games", isOn: $settings.shuffleGameOrder)
                Toggle("Start on Launch", isOn: $settings.startGameOnLaunch)
            }
            .toggleStyle(SwitchToggleStyle(tint: .cyan))
            .font(.caption).foregroundColor(.white)
        }
    }
    
    private var markersSection: some View {
        DisclosureGroup("Last move markers", isExpanded: $isMarkersExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                
                // --- SLIDERS HIDDEN (Hardcoded preferences) ---
                /*
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Panel Opacity")
                        Spacer()
                        Text(String(format: "%.0f%%", settings.panelOpacity * 100))
                            .monospacedDigit().foregroundColor(.white)
                    }
                    .font(.caption).foregroundColor(.white.opacity(0.8))
                    Slider(value: $settings.panelOpacity, in: 0.0...1.0).tint(.orange)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Glass Blur")
                        Spacer()
                        Text(String(format: "%.1f", settings.panelDiffusiveness))
                            .monospacedDigit().foregroundColor(.white)
                    }
                    .font(.caption).foregroundColor(.white.opacity(0.8))
                    Slider(value: $settings.panelDiffusiveness, in: 0.0...1.0).tint(.purple)
                }
                .padding(.bottom, 8)
                */
                // ----------------------------------------------
                
                Group {
                    Toggle("Move Numbers", isOn: $settings.showMoveNumbers)
                    Toggle("Dot", isOn: $settings.showLastMoveDot)
                    Toggle("Circle", isOn: $settings.showLastMoveCircle)
                    Toggle("Board Glow", isOn: $settings.showBoardGlow)
                    Toggle("Enhanced Glow", isOn: $settings.showEnhancedGlow)
                    Toggle("Drop Stone Animation", isOn: $settings.showDropInAnimation)
                        .disabled(app.viewMode == .view2D)
                        .foregroundColor(app.viewMode == .view2D ? .white.opacity(0.4) : .white)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .cyan))
            .font(.caption)
            .foregroundColor(.white)
            .padding(.leading, 10)
            .padding(.top, 5)
        }
        .font(.headline).foregroundColor(.white).accentColor(.white)
    }
    
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Library", systemImage: "books.vertical.fill")
                .font(.headline).foregroundColor(.white)
            
            HStack {
                Button(action: { app.promptForFolder() }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Choose Folder")
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.15)).cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                if let url = settings.folderURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            
            if !app.games.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(app.games) { wrapper in
                            Button(action: {
                                app.selectGame(wrapper)
                                close()
                                // Delayed Auto-Play
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    app.boardVM?.startAutoPlay()
                                }
                            }) {
                                GameListRow(wrapper: wrapper, isSelected: app.selection?.id == wrapper.id)
                            }
                            .buttonStyle(.plain)
                            Divider().background(Color.white.opacity(0.1))
                        }
                    }
                }
                .frame(height: 250)
                .background(Color.black.opacity(0.2)).cornerRadius(6)
            } else {
                Text("No games loaded").font(.caption).foregroundColor(.gray)
            }
        }
    }
    
    private var footerView: some View {
        HStack {
            Text("SGFPlayer Clean v1.0.47")
                .font(.caption2).foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.2))
    }
    
    private func close() {
        withAnimation(.easeInOut(duration: 0.45)) { isPresented = false }
    }
}

struct GameListRow: View {
    let wrapper: SGFGameWrapper
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if isSelected {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                }
                
                Text(wrapper.game.info.playerBlack ?? "?")
                    .fontWeight(.bold) +
                Text(" vs ") +
                Text(wrapper.game.info.playerWhite ?? "?")
                    .fontWeight(.bold)
                
                Spacer()
            }
            .font(.caption)
            .foregroundColor(isSelected ? .cyan : .white)
            
            HStack {
                Text(wrapper.game.info.date ?? "Unknown Date").font(.caption2).foregroundColor(.gray)
                Spacer()
                Text(wrapper.game.info.result ?? "").font(.caption).bold().foregroundColor(.yellow)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
    }
}
