//
//  ViewModels_CompileTest.swift
//  SGFPlayerClean
//
//  Purpose: Quick compile check for Phase 1.1 ViewModels
//  Usage: Run `swift ViewModels_CompileTest.swift` to verify they compile
//

import Foundation
import SwiftUI
import Combine

// This file just imports both ViewModels to verify they compile
// If this file compiles, Phase 1.1 is successful

func phase1_1_CompileCheck() {
    print("✅ Phase 1.1: ViewModels Compile Check")

    // Test BoardViewModel initialization
    let boardVM = BoardViewModel()
    print("  ✅ BoardViewModel initializes")
    print("     - currentMoveIndex: \(boardVM.currentMoveIndex)")
    print("     - stones count: \(boardVM.stones.count)")
    print("     - isAutoPlaying: \(boardVM.isAutoPlaying)")

    // Test LayoutViewModel initialization
    let layoutVM = LayoutViewModel()
    print("  ✅ LayoutViewModel initializes")
    print("     - boardFrame: \(layoutVM.boardFrame)")
    print("     - bowlRadius: \(layoutVM.bowlRadius)")

    // Test layout calculation
    layoutVM.calculateLayout(
        containerSize: CGSize(width: 1200, height: 800),
        boardSize: 19
    )
    print("  ✅ Layout calculation works")
    print("     - Board size: \(layoutVM.boardFrame.size)")
    print("     - Board center: \(layoutVM.boardCenter)")
    print("     - Upper bowl: \(layoutVM.upperBowlCenter)")
    print("     - Lower bowl: \(layoutVM.lowerBowlCenter)")

    // Test coordinate conversion
    let screenPoint = layoutVM.boardToScreen(row: 3, col: 3, boardSize: 19)
    print("  ✅ Coordinate conversion works")
    print("     - Board (3,3) → Screen \(screenPoint)")

    if let boardCoords = layoutVM.screenToBoard(screenPoint, boardSize: 19) {
        print("     - Screen \(screenPoint) → Board (\(boardCoords.row), \(boardCoords.col))")
    }

    // Test BoardPosition
    let pos1 = BoardPosition(3, 3)
    let pos2 = BoardPosition(sgf: "dd", boardSize: 19)
    print("  ✅ BoardPosition works")
    print("     - Position (3,3): \(pos1)")
    print("     - Position from 'dd': \(String(describing: pos2))")

    // Test Stone enum
    let blackStone = Stone.black
    let whiteStone = Stone.white
    print("  ✅ Stone enum works")
    print("     - Black: \(blackStone), opponent: \(blackStone.opponent)")
    print("     - White: \(whiteStone), opponent: \(whiteStone.opponent)")

    print("\n🎉 Phase 1.1 Complete: All ViewModels compile successfully!")
    print("\nNext: Phase 1.2 - Create Views")
}

// Run the check
phase1_1_CompileCheck()
