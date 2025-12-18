//
//  OGSCreateChallengeView.swift
//  SGFPlayerClean
//
//  v3.123: Revert to Sheet Layout.
//  - Standard Header layout with Cancel/Create buttons.
//  - Persistence enabled.
//  - Rank Logic enabled.
//  - Uses .presentationBackground(.ultraThinMaterial) for transparency.
//

import SwiftUI

struct OGSCreateChallengeView: View {
    @ObservedObject var client: OGSClient
    @Binding var isPresented: Bool
    
    @State private var setup = ChallengeSetup.load()
    @State private var isSending = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Header
            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("New Challenge")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Create") { submitChallenge() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isSending)
            }
            .padding()
            .background(Color.black.opacity(0.1))
            
            Divider().background(Color.white.opacity(0.15))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    
                    // Game Info
                    SectionHeader("Game Info")
                    VStack(spacing: 12) {
                        HStack { Text("Name"); Spacer(); TextField("Name", text: $setup.name).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 150) }
                        Divider().background(Color.white.opacity(0.1))
                        Toggle("Ranked", isOn: $setup.ranked)
                        Divider().background(Color.white.opacity(0.1))
                        HStack { Text("Color"); Spacer(); Picker("", selection: $setup.color) { Text("Auto").tag("automatic"); Text("Black").tag("black"); Text("White").tag("white") }.labelsHidden().fixedSize() }
                        Divider().background(Color.white.opacity(0.1))
                        HStack { Text("Handicap"); Spacer(); Picker("", selection: $setup.handicap) { Text("None").tag(0); ForEach(2...9, id: \.self) { i in Text("\(i)").tag(i) } }.labelsHidden().fixedSize() }
                    }
                    .padding()
                    
                    Divider().background(Color.white.opacity(0.15))
                    
                    // Board
                    SectionHeader("Board")
                    VStack(spacing: 12) {
                        Picker("", selection: $setup.size) { Text("19x19").tag(19); Text("13x13").tag(13); Text("9x9").tag(9) }.pickerStyle(.segmented)
                        Divider().background(Color.white.opacity(0.1))
                        HStack { Text("Rules"); Spacer(); Picker("", selection: $setup.rules) { Text("Japanese").tag("japanese"); Text("Chinese").tag("chinese"); Text("AGA").tag("aga") }.labelsHidden().fixedSize() }
                    }
                    .padding()
                    
                    Divider().background(Color.white.opacity(0.15))
                    
                    // Time Control
                    SectionHeader("Time Control")
                    VStack(spacing: 12) {
                        Picker("", selection: $setup.timeControl) { Text("Byoyomi").tag("byoyomi"); Text("Fischer").tag("fischer"); Text("Simple").tag("simple") }.pickerStyle(.segmented)
                        Divider().background(Color.white.opacity(0.1))
                        if setup.timeControl == "byoyomi" {
                            TimeFieldRow(label: "Main Time", value: $setup.mainTime)
                            TimeFieldRow(label: "Period Time", value: $setup.periodTime)
                            HStack { Text("Periods"); Spacer(); Stepper("\(setup.periods)", value: $setup.periods, in: 1...10) }
                        } else if setup.timeControl == "fischer" {
                            TimeFieldRow(label: "Initial", value: $setup.initialTime)
                            TimeFieldRow(label: "Increment", value: $setup.increment)
                            TimeFieldRow(label: "Max", value: $setup.maxTime)
                        } else {
                            TimeFieldRow(label: "Per Move", value: $setup.perMove)
                        }
                    }
                    .padding()
                    
                    Divider().background(Color.white.opacity(0.15))
                    
                    // Rank Range
                    SectionHeader("Rank Range")
                    VStack(spacing: 12) {
                        HStack { Text("Min: \(formatRank(setup.minRank))"); Spacer(); Stepper("", value: $setup.minRank, in: 0...setup.maxRank).onChange(of: setup.minRank) { v in if v > setup.maxRank { setup.maxRank = v } } }
                        Divider().background(Color.white.opacity(0.1))
                        HStack { Text("Max: \(formatRank(setup.maxRank))"); Spacer(); Stepper("", value: $setup.maxRank, in: setup.minRank...38).onChange(of: setup.maxRank) { v in if v < setup.minRank { setup.minRank = v } } }
                    }
                    .padding()
                    
                    if let error = errorMessage {
                        Text(error).foregroundColor(.red).font(.caption).padding()
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 400, minHeight: 650)
        // Standard SwiftUI material backing for sheets
        .presentationBackground(.ultraThinMaterial)
    }
    
    private func submitChallenge() {
        setup.save()
        isSending = true; errorMessage = nil
        client.createChallenge(setup: setup) { success, error in
            DispatchQueue.main.async {
                isSending = false
                if success { isPresented = false; if !client.isSubscribedToSeekgraph { client.subscribeToSeekgraph(force: true) } }
                else { errorMessage = error ?? "Unknown error" }
            }
        }
    }
    
    private func formatRank(_ val: Int) -> String { val < 30 ? "\(30 - val)k" : "\(val - 29)d" }
}

struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption).fontWeight(.bold)
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.top, 16)
    }
}

struct TimeFieldRow: View {
    let label: String; @Binding var value: Int
    var body: some View { HStack { Text(label); Spacer(); TextField("", value: $value, format: .number).textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 50).padding(4).background(Color.white.opacity(0.1)).cornerRadius(4); Text("s").foregroundColor(.gray) } }
}
