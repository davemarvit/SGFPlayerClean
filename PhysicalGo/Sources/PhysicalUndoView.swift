import SwiftUI
import AppKit

struct PhysicalUndoView: View {
    @ObservedObject var controller: PhysicalUndoController
    let moveInFlight: Bool
    @State private var confirmRequest = false
    @State private var requestContext: PhysicalUndoController.Context?
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let state = controller.state {
                if let requester = state.requester, !state.requesting {
                    Text("\(requester) requests an undo.").font(.headline)
                    HStack {
                        Button("Decline") { controller.send(.cancel) }
                        Button("Accept undo") { controller.send(.accept) }
                    }.disabled(!state.available || controller.awaitingCommand)
                    Text("Wait for OGS to update the board, then restore the marked stones.").font(.caption)
                } else if state.requesting {
                    Text("Undo requested · waiting for the opponent or OGS.")
                    Button("Cancel undo request") { controller.send(.cancel) }
                        .disabled(!state.available || controller.awaitingCommand)
                } else {
                    Button("Request undo…", systemImage: "arrow.uturn.backward") { requestContext = controller.context; confirmRequest = true }
                        .disabled(!state.available || state.moveNumber == 0 || controller.awaitingCommand || moveInFlight)
                    Text("Online undo needs the opponent’s approval. The server clock continues.").font(.caption)
                }
                if let message = controller.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            } else {
                Button("Undo in SGF Player…") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.davemarvit.SGFPlayerClean") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
                Text("Use Undo in SGF Player’s active game. Updated versions also provide online undo here.").font(.caption).foregroundStyle(.secondary)
            }
        }.onAppear { controller.refresh() }.onReceive(timer) { _ in controller.refresh() }
            .confirmationDialog("Request undo from your opponent?", isPresented: $confirmRequest, titleVisibility: .visible) {
                Button("Request undo") { controller.send(.request, expectedContext: requestContext) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Leave the stones in place until OGS approves the takeback. The server clock continues running.") }
    }
}
