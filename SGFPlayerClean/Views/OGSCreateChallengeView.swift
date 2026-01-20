// MARK: - File: OGSCreateChallengeView.swift (v4.200)
import SwiftUI

struct OGSCreateChallengeView: View {
    @EnvironmentObject var app: AppModel
    @Binding var isPresented: Bool
    @State private var setup = ChallengeSetup.load()
    @State private var isSending = false
    @State private var errorMessage: String?
    
    // Fix: Track focus to disable global shortcuts when typing name.
    @FocusState private var isNameFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().background(Color.white.opacity(0.2))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    gameInfoSection
                    Divider().background(Color.white.opacity(0.15))
                    boardSection
                    Divider().background(Color.white.opacity(0.15))
                    timeControlSection
                    Divider().background(Color.white.opacity(0.15))
                    rankRangeSection
                    if let error = errorMessage { Text(error).foregroundColor(.red).font(.caption).padding() }
                }
            }.scrollContentBackground(.hidden)
        }
        // Bind Focus State to AppModel to disable global shortcuts
        .onChange(of: isNameFocused) { focused in app.isTypingInChat = focused }
        .onDisappear { app.isTypingInChat = false }
    }
    
    private var headerSection: some View {
        HStack {
            Button(action: { isPresented = false }) { Text("Cancel").foregroundColor(.white.opacity(0.8)) }.buttonStyle(.plain)
            Spacer(); Text("Challenge").font(.headline).foregroundColor(.white); Spacer()
            Button(action: submitChallenge) {
                if isSending { ProgressView().controlSize(.small) }
                else { Text("Issue").fontWeight(.bold).foregroundColor(.white) }
            }.buttonStyle(.borderedProminent).tint(.green).disabled(isSending)
        }.padding().background(Color.black.opacity(0.1))
    }
    
    private var gameInfoSection: some View {
        VStack(alignment: .leading) {
            SectionHeader(text: "Game Info")
            VStack(spacing: 12) {
                // Name Field
                VStack(alignment: .leading) {
                    Text("Name").font(.caption).foregroundColor(.gray)
                    TextField("Name", text: $setup.name)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                        .focused($isNameFocused) // Bind Focus
                        // Keep onKeyPress as backup/safety if focus logic lags
                        .onKeyPress(.space) { setup.name += " "; return .handled }
                }
                
                // Ranked Toggle (Own Line)
                Toggle("Ranked Game", isOn: $setup.ranked)
                
                // Color Row
                HStack {
                    Text("Your Color"); Spacer()
                    Picker("", selection: $setup.color) {
                        Text("Auto").tag("automatic")
                        Text("Black").tag("black")
                        Text("White").tag("white")
                    }.labelsHidden().fixedSize()
                }
                
                // Handicap Row
                HStack {
                    Text("Handicap"); Spacer()
                    Picker("", selection: $setup.handicap) {
                        Text("Auto").tag(-1)
                        Text("None").tag(0)
                        ForEach(2...9, id: \.self) { i in Text("\(i)").tag(i) }
                    }.labelsHidden().fixedSize()
                }
            }.padding()
        }
    }

    private var boardSection: some View {
        VStack(alignment: .leading) {
            SectionHeader(text: "Board")
            VStack(spacing: 12) {
                Picker("", selection: $setup.size) {
                    Text("19x19").tag(19)
                    Text("13x13").tag(13)
                    Text("9x9").tag(9)
                }.pickerStyle(.segmented)
                
                HStack {
                    Text("Rules"); Spacer()
                    Picker("", selection: $setup.rules) {
                        Text("Japanese").tag("japanese")
                        Text("Chinese").tag("chinese")
                        Text("AGA").tag("aga")
                    }.labelsHidden().fixedSize()
                }
            }.padding()
        }
    }
    
    private var timeControlSection: some View {
        VStack(alignment: .leading) {
            SectionHeader(text: "Time Control")
            VStack(spacing: 12) {
                Picker("", selection: $setup.timeControl) {
                    Text("Byoyomi").tag("byoyomi")
                    Text("Fischer").tag("fischer")
                    Text("Simple").tag("simple")
                }.pickerStyle(.segmented)
                
                if setup.timeControl == "byoyomi" {
                    TimeFieldRow(label: "Main Time", value: $setup.mainTime, showMinutes: true, showSeconds: true)
                    TimeFieldRow(label: "Period Time", value: $setup.periodTime, showMinutes: true, showSeconds: true)
                    HStack { Text("Periods"); Spacer(); Stepper("\(setup.periods)", value: $setup.periods, in: 1...10) }
                } else if setup.timeControl == "fischer" {
                    TimeFieldRow(label: "Initial Time", value: $setup.initialTime, showMinutes: true, showSeconds: true)
                    TimeFieldRow(label: "Increment", value: $setup.increment, showMinutes: true, showSeconds: true)
                    TimeFieldRow(label: "Max Time", value: $setup.maxTime, showMinutes: true, showSeconds: true)
                } else {
                    TimeFieldRow(label: "Per Move", value: $setup.perMove, showMinutes: true, showSeconds: true)
                }
            }.padding()
        }
    }
    
    private var rankRangeSection: some View {
        VStack(alignment: .leading) {
            SectionHeader(text: "Rank Range")
            VStack(spacing: 12) {
                HStack {
                    Text("Min: \(formatRank(setup.minRank))")
                    Spacer()
                    Stepper("", value: $setup.minRank, in: 0...setup.maxRank).labelsHidden()
                }
                HStack {
                    Text("Max: \(formatRank(setup.maxRank))")
                    Spacer()
                    Stepper("", value: $setup.maxRank, in: setup.minRank...38).labelsHidden()
                }
            }.padding()
        }
    }

    private func submitChallenge() {
        // Reset typing flag when submitting
        app.isTypingInChat = false
        setup.save(); isSending = true; errorMessage = nil
        app.ogsClient.createChallenge(setup: setup) { success, _ in
            DispatchQueue.main.async { self.isSending = false; if success { isPresented = false } else { errorMessage = "Creation failed" } }
        }
    }
    private func formatRank(_ val: Int) -> String { val < 30 ? "\(30 - val)k" : "\(val - 29)d" }

    struct SectionHeader: View {
        let text: String
        var body: some View { Text(text).font(.caption).fontWeight(.bold).foregroundColor(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 16) }
    }
    
    struct TimeFieldRow: View {
        let label: String
        @Binding var value: Int
        var showMinutes: Bool = true
        var showSeconds: Bool = true
        
        var body: some View {
            HStack {
                Text(label)
                Spacer()
                
                if showMinutes {
                    let minBinding = Binding<Int>(
                        get: { value / 60 },
                        set: {
                            let oldSecs = value % 60
                            value = ($0 * 60) + oldSecs
                        }
                    )
                    HStack(spacing: 2) {
                        TextField("M", value: minBinding, format: .number)
                            .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                            .frame(width: 35).padding(4).background(Color.white.opacity(0.1)).cornerRadius(4)
                        Text("m").font(.caption).foregroundColor(.gray)
                    }
                }
                
                if showSeconds {
                    let secBinding = Binding<Int>(
                        get: { value % 60 },
                        set: {
                            let oldMins = value / 60
                            value = (oldMins * 60) + $0
                        }
                    )
                    HStack(spacing: 2) {
                        TextField("S", value: secBinding, format: .number)
                            .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                            .frame(width: 35).padding(4).background(Color.white.opacity(0.1)).cornerRadius(4)
                        Text("s").font(.caption).foregroundColor(.gray)
                    }
                }
            }
        }
    }
}
