// MARK: - File: ContentView.swift (v7.201)
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showSettings: Bool = false
    @State private var buttonsVisible: Bool = true

    var body: some View {
        ZStack {
            mainInterface // .disabled(appModel.isCreatingChallenge) removed
            SharedOverlays(showSettings: $showSettings, buttonsVisible: $buttonsVisible, app: appModel)
            VStack {
                HStack {
                    Spacer()
                    // Debug Icon Removed
                }
                Spacer()
            }
            VStack {
                HStack {
                    Spacer()
                    // Debug Icon Removed
                }
                Spacer()
            }
            // Challenge View Removed (Moved to Right Panel)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appModel.showDebugDashboard) { DebugDashboard(appModel: appModel).frame(minWidth: 700, minHeight: 500) }
    }

    @ViewBuilder
    private var mainInterface: some View {
        if appModel.viewMode == .view3D { ContentView3D() }
        else { ContentView2D() }
    }
}
