// MARK: - File: ContentView.swift (v7.201)
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showSettings: Bool = false
    @State private var buttonsVisible: Bool = true

    var body: some View {
        ZStack {
            mainInterface.disabled(appModel.isCreatingChallenge)
            SharedOverlays(showSettings: $showSettings, buttonsVisible: $buttonsVisible, app: appModel)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { appModel.showDebugDashboard.toggle() }) {
                        Image(systemName: "ladybug.fill").foregroundColor(appModel.ogsClient.isConnected ? .green : .red)
                            .padding(8).background(Color.black.opacity(0.6)).clipShape(Circle())
                    }.buttonStyle(.plain).padding()
                }
                Spacer()
            }
            if appModel.isCreatingChallenge {
                OGSCreateChallengeView(isPresented: $appModel.isCreatingChallenge).background(Color.black.opacity(0.6)).transition(.opacity).zIndex(200)
            }
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
