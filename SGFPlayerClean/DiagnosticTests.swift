//
//  DiagnosticTests.swift
//  SGFPlayerClean
//
//  Purpose: Diagnostic test views for debugging performance issues
//  These were used to isolate the spinning ball (infinite render loop) bug
//  Keep for future debugging if needed
//

import SwiftUI

// MARK: - Diagnostic Test Views

// TEST 1: Absolute minimal - no dependencies
struct Test1_Minimal: View {
    var body: some View {
        Text("Test 1: Minimal - No dependencies")
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onAppear { print("✅ Test 1: Minimal appeared") }
    }
}

// TEST 2: With AppModel created but not used in view
struct Test2_AppModel: View {
    @StateObject private var appModel = AppModel()

    var body: some View {
        Text("Test 2: AppModel exists (not used)")
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onAppear { print("✅ Test 2: AppModel test appeared") }
    }
}

// TEST 3: BoardViewModel WITHOUT Combine subscriptions
struct Test3_BoardVMNoCombine: View {
    @StateObject private var boardVM = BoardViewModel_NoCombine()

    var body: some View {
        VStack {
            Text("Test 3: BoardViewModel WITHOUT Combine")
                .foregroundColor(.white)
            Text("Stones: \(boardVM.stones.count)")
                .foregroundColor(.white)
            Text("Move: \(boardVM.currentMoveIndex)")
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { print("✅ Test 3: BoardVM (no Combine) appeared") }
    }
}

// Stripped-down BoardViewModel with NO Combine subscriptions
class BoardViewModel_NoCombine: ObservableObject {
    @Published var stones: [BoardPosition: Stone] = [:]
    @Published var currentMoveIndex: Int = 0
    @Published var boardSize: Int = 19

    private var player: SGFPlayer

    init() {
        self.player = SGFPlayer()
        // CRITICAL: NO setupPlayerObservers() call!
        print("✅ BoardViewModel_NoCombine init: NO Combine subscriptions")
    }
}

// TEST 4: Full BoardViewModel WITH Combine subscriptions
struct Test4_FullBoardVM: View {
    @StateObject private var appModel = AppModel()
    @StateObject private var boardVM: BoardViewModel

    init() {
        let model = AppModel()
        _appModel = StateObject(wrappedValue: model)
        _boardVM = StateObject(wrappedValue: BoardViewModel(player: model.player))
        print("✅ Test 4: Full BoardViewModel initialized")
    }

    var body: some View {
        VStack {
            Text("Test 4: Full BoardViewModel WITH Combine")
                .foregroundColor(.white)
            Text("Stones: \(boardVM.stones.count)")
                .foregroundColor(.white)
            Text("Move: \(boardVM.currentMoveIndex)")
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { print("✅ Test 4: Full BoardVM appeared") }
    }
}

// MARK: - Usage Instructions

/*
 To use these diagnostic tests, replace ContentView2D() in SGFPlayerCleanApp.swift with:

 Test1_Minimal()     // Expected: 0% CPU
 Test2_AppModel()    // Expected: 0% CPU
 Test3_BoardVMNoCombine()  // Expected: 0% CPU
 Test4_FullBoardVM()  // Expected: 0% CPU

 This systematic approach helps isolate performance issues layer by layer.
 */
