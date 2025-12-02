//
//  BoardSnapshot.swift
//  SGFPlayerClean
//
//  Purpose: Board state representation
//  Copied from old codebase
//
//  Note: Stone enum is defined in SGFKit.swift
//

import Foundation

/// Snapshot of the board state at a particular position
struct BoardSnapshot: Equatable {
    let size: Int
    let grid: [[Stone?]] // [y][x]
}
