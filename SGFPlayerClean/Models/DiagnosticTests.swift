// MARK: - File: DiagnosticTests.swift (v4.212)
//
//  Purpose: Diagnostic test views for debugging performance issues
//

import SwiftUI

// TEST 4: Full BoardViewModel WITH Combine subscriptions
struct Test4_FullBoardVM: View {
    @StateObject private var appModel = AppModel()
    @StateObject private var boardVM: BoardViewModel

    init() {
        let model = AppModel()
        _appModel = StateObject(wrappedValue: model)
        // Harmonized signature matching v8.100 architecture
        _boardVM = StateObject(wrappedValue: BoardViewModel(player: model.player, ogsClient: model.ogsClient))
        print("✅ Test 4: Full BoardViewModel initialized")
    }

    var body: some View {
        VStack {
            Text("Test 4: Full BoardViewModel WITH Combine")
                .foregroundColor(.white)
            // Performance Fix: Use optimized stonesToRender count
            Text("Stones (Cache): \(boardVM.stonesToRender.count)")
                .foregroundColor(.white)
            Text("Move: \(boardVM.currentMoveIndex)")
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { print("✅ Test 4: Full BoardVM appeared") }
    }
}

// Minimal Test 1
struct Test1_Minimal: View {
    var body: some View {
        Text("Test 1: Minimal - No dependencies")
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onAppear { print("✅ Test 1: Minimal appeared") }
    }
}

// Test 2
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

// Test 3
struct Test3_BoardVMNoCombine: View {
    @StateObject private var boardVM = BoardViewModel_NoCombine()
    var body: some View {
        VStack {
            Text("Test 3: BoardViewModel WITHOUT Combine")
                .foregroundColor(.white)
            Text("Stones: \(boardVM.stones.count)")
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { print("✅ Test 3: BoardVM (no Combine) appeared") }
    }
}

class BoardViewModel_NoCombine: ObservableObject {
    @Published var stones: [BoardPosition: Stone] = [:]
    @Published var currentMoveIndex: Int = 0
    init() {}
}
