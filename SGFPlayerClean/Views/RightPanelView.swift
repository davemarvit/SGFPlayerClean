
//  RightPanelView.swift
//  SGFPlayerClean
//
//  Created: 2025-12-01
//  Purpose: Unified Right Panel (Toggle + Content) shared by 2D and 3D
//

import SwiftUI

struct RightPanelView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var boardVM: BoardViewModel
    
    var body: some View {
        ZStack(alignment: .top) {
            // Invisible background to catch clicks if needed
            Color.black.opacity(0.01)
            
            VStack(spacing: 0) {
                // 1. Mode Switcher
                Picker("Mode", selection: $app.isOnlineMode) {
                    Text("Local").tag(false)
                    Text("Online").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 20) // Consistent top padding
                .padding(.bottom, 10)
                
                // 2. Content Area
                if app.isOnlineMode {
                    OGSBrowserView(app: app)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 20)
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    VStack {
                        GameInfoCard(
                            boardVM: boardVM,
                            ogsVM: app.ogsGame
                        )
                        .padding(.top, 10)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                }
            }
        }
    }
}
