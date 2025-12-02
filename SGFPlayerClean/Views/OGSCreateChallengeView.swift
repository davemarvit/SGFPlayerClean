import SwiftUI

struct OGSCreateChallengeView: View {
    @ObservedObject var app: AppModel
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { withAnimation { isPresented = false } }) {
                    HStack { Image(systemName: "chevron.left"); Text("Back") }
                        .foregroundColor(.white).padding(8).background(Color.white.opacity(0.1)).cornerRadius(6)
                }.buttonStyle(.plain)
                
                Spacer()
                Text("New Game").font(.headline).foregroundColor(.white)
                Spacer()
                Text("Back").hidden() // Balance
            }
            .padding().background(Color.black.opacity(0.3))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Info
                    Text("Info").font(.caption).fontWeight(.bold).foregroundColor(.gray).padding(.horizontal)
                    TextField("Game Name", text: $app.gameSettings.gameName).textFieldStyle(.plain).padding(8).background(Color.white.opacity(0.1)).cornerRadius(4).padding(.horizontal)

                    // 2. Settings
                    Text("Board").font(.caption).fontWeight(.bold).foregroundColor(.gray).padding(.horizontal)
                    VStack(spacing: 15) {
                        Picker("Size", selection: $app.gameSettings.boardSize) {
                            Text("19x19").tag(19); Text("13x13").tag(13); Text("9x9").tag(9)
                        }.pickerStyle(.segmented)
                        
                        Toggle("Ranked", isOn: $app.gameSettings.ranked).toggleStyle(.switch)
                    }.padding(.horizontal)
                    
                    // 3. Create
                    Button(action: createGame) {
                        Text("Create Challenge").font(.headline).frame(maxWidth: .infinity).padding().background(Color.green).foregroundColor(.white).cornerRadius(8)
                    }.buttonStyle(.plain).padding()
                }.padding(.vertical)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func createGame() {
        app.gameSettings.save()
        app.ogsClient.postCustomGame(settings: app.gameSettings) { success, error in
            if success {
                DispatchQueue.main.async {
                    withAnimation { isPresented = false }
                    app.ogsClient.subscribeToSeekgraph(force: true)
                }
            }
        }
    }
}
