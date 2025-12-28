// MARK: - File: ContentView.swift (v3.400)
import SwiftUI

struct ContentView: View {
    @StateObject var appModel = AppModel()

    var body: some View {
        ZStack {
            // Main Interface
            mainInterface
                .disabled(appModel.isCreatingChallenge)
            
            // Top-right Debug Toggle (Manual Override)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { appModel.showDebugDashboard.toggle() }) {
                        Image(systemName: "ladybug.fill")
                            .foregroundColor(appModel.ogsClient.isConnected ? .green : .red)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
                Spacer()
            }
            
            if appModel.isCreatingChallenge {
                OGSCreateChallengeView(isPresented: $appModel.isCreatingChallenge)
                    .background(Color.black.opacity(0.6))
                    .transition(.opacity)
                    .zIndex(200)
            }
        }
        .environmentObject(appModel)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appModel.showDebugDashboard) {
            DebugDashboard(appModel: appModel)
                .frame(minWidth: 700, minHeight: 500)
        }
    }

    @ViewBuilder
    private var mainInterface: some View {
        if appModel.viewMode == .view3D {
            ContentView3D()
        } else {
            ContentView2D()
        }
    }
}
