//
//  SettingsPanel.swift
//  SGFPlayerClean
//
//  Created: 2025-12-01
//  Purpose: Slide-out settings drawer with visual preferences and library management
//

import SwiftUI

struct SettingsPanel: View {
    @Environment(\.interfaceTextScale) private var textScale
    @ObservedObject var app: AppModel
    @ObservedObject var settings = AppSettings.shared
    @Binding var isPresented: Bool
    
    @AppStorage("settings.environment.expanded") private var isEnvironmentExpanded = true
    @AppStorage("settings.playback.expanded") private var isPlaybackExpanded = false
    @AppStorage("settings.markers.expanded") private var isMarkersExpanded = false
    @AppStorage("settings.ai.expanded") private var isAIExpanded = false
    @AppStorage("settings.screensaver.expanded") private var isScreensaverExpanded = false
    @AppStorage("settings.library.expanded") private var isLibraryExpanded = false
    @AppStorage("settings.savedGames.expanded") private var isSavedGamesExpanded = false
    
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
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                ViewThatFits(in: .vertical) {
                    drawerContent.fixedSize(horizontal: false, vertical: true)
                    ScrollView { drawerContent }
                }
                .frame(width: min(geo.size.width - 20, 350 * textScale))
                .frostedGlassStyle()
                .padding(10)
                .transition(.move(edge: .leading))
            }
        }
        .zIndex(100)
    }
    
    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            VStack(alignment: .leading, spacing: 12) {
                textSizeSection
                Divider().background(Color.white.opacity(0.3))
                environmentSection
                Divider().background(Color.white.opacity(0.3))
                playbackSection
                Divider().background(Color.white.opacity(0.3))
                markersSection
                Divider().background(Color.white.opacity(0.3))
                aiSection
                Divider().background(Color.white.opacity(0.3))
                DisclosureGroup(isExpanded: $isScreensaverExpanded) {
                    ScreensaverSettingsView(manager: .shared, showsHeading: false)
                } label: {
                    Label("Screensaver", systemImage: "display")
                }
                Divider().background(Color.white.opacity(0.3))
                librarySection
                Divider().background(Color.white.opacity(0.3))
                DisclosureGroup(isExpanded: $isSavedGamesExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(settings.savedGamesFolderURL.path)
                            .interfaceFont(.caption).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Change Save Folder…") { app.chooseGameSaveFolder() }
                        Text("Finished games save automatically. Review edits update a separate review file. Save SGF also remembers the folder you choose; existing reviews keep their saved location.")
                            .interfaceFont(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } label: { Label("Saved Games", systemImage: "folder.badge.gearshape") }
            }
            .disclosureGroupStyle(SettingsDisclosureStyle())
            .padding()
            footerView
        }
    }

    // MARK: - Components
    
    private var headerView: some View {
        HStack {
            Text("Settings")
                .interfaceFont(.title2, weight: .bold)
                .foregroundColor(.white)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .interfaceFont(.title2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.black.opacity(0.1))
    }
    
    private var textSizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Text size", systemImage: "textformat.size")
                Spacer()
                Text("\(Int((settings.interfaceTextScale * 100).rounded()))%")
                    .monospacedDigit()
            }
            Slider(value: $settings.interfaceTextScale, in: 1...1.6, step: 0.1)
                .accessibilityLabel("Text size")
                .accessibilityIdentifier("interface-text-size")
            Text("Text also grows automatically in larger windows.")
                .interfaceFont(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var environmentSection: some View {
        DisclosureGroup(isExpanded: $isEnvironmentExpanded) {
            Picker("Environment", selection: $settings.environment3D) {
                ForEach(PlayingEnvironment.allCases) { environment in
                    Text(environment.title).tag(environment)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("3D environment")
            .accessibilityIdentifier("environment-picker")
            Text(settings.environment3D.detail)
                .interfaceFont(.caption).foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if settings.environment3D == .cave {
                Toggle("Gentle lamp flicker", isOn: $settings.lampFlicker)
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                    .interfaceFont(.caption).foregroundColor(.white)
                    .accessibilityIdentifier("lamp-flicker-toggle")
            }
            if app.viewMode == .view2D {
                Button("Switch to 3D") { app.viewMode = .view3D }
            }
        } label: {
            Label("3D environment", systemImage: settings.environment3D.symbol)
        }
    }

    private var playbackSection: some View {
        DisclosureGroup(isExpanded: $isPlaybackExpanded) {
            
            // Delay Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Move Delay")
                    Spacer()
                    Text(String(format: "%.1fs", settings.moveInterval))
                        .monospacedDigit().foregroundColor(.white)
                }
                .interfaceFont(.caption).foregroundColor(.white.opacity(0.8))
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
                .interfaceFont(.caption).foregroundColor(.white.opacity(0.8))
                Slider(value: $settings.jitterMultiplier, in: 0.0...2.0, step: 0.05).tint(.cyan)
            }
            
            // Volume Sliders
            VStack(alignment: .leading, spacing: 4) {
                 HStack {
                     Text("Stone Volume") // Placement & Capture
                     Spacer()
                     Text(String(format: "%.0f%%", settings.stoneVolume * 100)).monospacedDigit().foregroundColor(.white)
                 }
                 .interfaceFont(.caption).foregroundColor(.white.opacity(0.8))
                 Slider(value: $settings.stoneVolume, in: 0.0...1.0).tint(.green)

                 HStack {
                     Text("Voice Volume") // System & Speech
                     Spacer()
                     Text(String(format: "%.0f%%", settings.voiceVolume * 100)).monospacedDigit().foregroundColor(.white)
                 }
                 .interfaceFont(.caption).foregroundColor(.white.opacity(0.8))
                 Slider(value: $settings.voiceVolume, in: 0.0...1.0).tint(.cyan)
            }
            
            Group {
                Toggle("Show Board Coordinates", isOn: $settings.showBoardCoordinates)
                    .help("Letters across, skipping I; numbers count up from the bottom. A1 is the lower-left intersection.")
                    .accessibilityIdentifier("show-board-coordinates")
                Toggle("Shuffle Games", isOn: $settings.shuffleGameOrder)
                Toggle("Start on Launch", isOn: $settings.startGameOnLaunch)
            }
            .toggleStyle(SwitchToggleStyle(tint: .cyan))
            .interfaceFont(.caption).foregroundColor(.white)
        } label: {
            Label("Playback", systemImage: "play.circle.fill")
        }
    }
    
    private var markersSection: some View {
        DisclosureGroup(isExpanded: $isMarkersExpanded) {
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
                    .interfaceFont(.caption).foregroundColor(.white.opacity(0.8))
                    Slider(value: $settings.panelOpacity, in: 0.0...1.0).tint(.orange)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Glass Blur")
                        Spacer()
                        Text(String(format: "%.1f", settings.panelDiffusiveness))
                            .monospacedDigit().foregroundColor(.white)
                    }
                    .interfaceFont(.caption).foregroundColor(.white.opacity(0.8))
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
            .interfaceFont(.caption)
            .foregroundColor(.white)
            
            // 3D Camera Reset Control
            Button(action: {
                settings.camera3DRotationX = 0.45
                settings.camera3DRotationY = 0.0
                settings.camera3DDistance = 25.0
                settings.camera3DPanX = 0.0
                settings.camera3DPanY = 0.0
            }) {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("Reset 3D Camera Default")
                }
                .interfaceFont(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(app.viewMode == .view2D ? Color.white.opacity(0.05) : Color.blue.opacity(0.8))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(app.viewMode == .view2D)
            .foregroundColor(app.viewMode == .view2D ? .white.opacity(0.4) : .white)
            .padding(.top, 8)
        } label: {
            Label("Last move markers", systemImage: "circle.dotted")
        }
    }
    
    private var aiSection: some View {
        DisclosureGroup(isExpanded: $isAIExpanded) {
            Toggle("Enable analysis", isOn: $settings.analysisEnabled)
                .accessibilityIdentifier("settings.analysisEnabled")
            Text("Turn off to stop all AI analysis and hide its results. Saved analysis is kept.")
                .interfaceFont(.caption).foregroundColor(.secondary)
            Toggle("Analyze quietly during play", isOn: $settings.analyzeDuringPlay)
                .disabled(!settings.analysisEnabled)
            Toggle("Pause background analysis on battery", isOn: $settings.pauseAnalysisOnBattery)
                .disabled(!settings.analysisEnabled)
            Text("Results stay hidden until the game ends. Background analysis pauses in Low Power Mode and when your Mac is busy or warm.")
                .interfaceFont(.caption).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("KataGo Executable Path")
                    .interfaceFont(.caption).foregroundColor(.white.opacity(0.8))
                TextField("/opt/homebrew/bin/katago", text: $settings.customKataGoPath)
                    .textFieldStyle(.roundedBorder)
                    .interfaceFont(.caption)
                    .onChange(of: settings.customKataGoPath) { _, _ in
                        if settings.analysisEnabled { KataGoEngine.shared.restart() }
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Neural Net Model (.bin.gz)")
                    .interfaceFont(.caption).foregroundColor(.white.opacity(0.8))
                TextField("Optional custom model path", text: $settings.customAIModelPath)
                    .textFieldStyle(.roundedBorder)
                    .interfaceFont(.caption)
                    .onChange(of: settings.customAIModelPath) { _, _ in
                        if settings.analysisEnabled { KataGoEngine.shared.restart() }
                    }
            }
        } label: {
            Label("AI Engine", systemImage: "cpu")
        }
        .toggleStyle(SwitchToggleStyle(tint: .cyan))
        .interfaceFont(.caption).foregroundColor(.white)
    }
    
    private var librarySection: some View {
        DisclosureGroup(isExpanded: $isLibraryExpanded) {
            
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .interfaceFont(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text(app.loadingStatus)
                            .interfaceFont(.caption)
                            .foregroundColor(app.loadingStatus.contains("❌") ? .red : (app.loadingStatus.contains("✅") ? .green : .cyan))
                            .fixedSize(horizontal: false, vertical: true)

                        Divider().padding(.vertical, 8)
                        Text("Last OGS Event:")
                            .interfaceFont(.caption2).foregroundColor(.gray)
                        Text(app.lastDebugLog)
                            .interfaceFont(.caption2).foregroundColor(.yellow)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                Text("No games loaded").interfaceFont(.caption).foregroundColor(.gray)
            }
        } label: {
            Label("Library", systemImage: "books.vertical.fill")
        }
    }
    
    private var footerView: some View {
        HStack {
            Text("SGFPlayer Clean v1.0.47")
                .interfaceFont(.caption2).foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.2))
    }
    
    private func close() {
        withAnimation(.easeInOut(duration: 0.45)) { isPresented = false }
    }
}

private struct SettingsDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: "chevron.right")
                        .interfaceFont(.caption, weight: .bold)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .interfaceFont(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Show or hide this section")

            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    configuration.content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
                        .interfaceFont(.caption2)
                        .foregroundColor(.cyan)
                }
                
                Text(wrapper.game.info.playerBlack ?? "?")
                    .fontWeight(.bold) +
                Text(" vs ") +
                Text(wrapper.game.info.playerWhite ?? "?")
                    .fontWeight(.bold)
                
                Spacer()
            }
            .interfaceFont(.caption)
            .foregroundColor(isSelected ? .cyan : .white)
            
            HStack {
                Text(wrapper.game.info.date ?? "Unknown Date").interfaceFont(.caption2).foregroundColor(.gray)
                Spacer()
                Text(wrapper.game.info.result ?? "").interfaceFont(.caption).bold().foregroundColor(.yellow)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
    }
}
