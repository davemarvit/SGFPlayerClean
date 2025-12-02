//
//  KeyboardShortcuts.swift
//  SGFPlayerClean
//
//  Created: 2025-11-26
//  Purpose: Reusable keyboard shortcuts for game navigation
//
//  ARCHITECTURE:
//  - ViewModifier for keyboard handling
//  - Reusable by both ContentView2D and ContentView3D
//  - All shortcuts in one place
//

import SwiftUI

/// ViewModifier that adds keyboard shortcuts for game navigation
struct KeyboardShortcutsModifier: ViewModifier {
    let boardVM: BoardViewModel

    func body(content: Content) -> some View {
        content
            .focusable()
            // Basic navigation
            .onKeyPress(.leftArrow, action: {
                print("⌨️ Left arrow pressed")
                boardVM.previousMove()
                return .handled
            })
            .onKeyPress(.rightArrow, action: {
                print("⌨️ Right arrow pressed")
                boardVM.nextMove()
                return .handled
            })
            .onKeyPress(.upArrow, action: {
                print("⌨️ Up arrow pressed")
                boardVM.goToStart()
                return .handled
            })
            .onKeyPress(.downArrow, action: {
                print("⌨️ Down arrow pressed")
                boardVM.goToEnd()
                return .handled
            })
            .onKeyPress(.space, action: {
                print("⌨️ Space pressed")
                boardVM.toggleAutoPlay()
                return .handled
            })
            .onKeyPress(.escape, action: {
                print("⌨️ Escape pressed")
                if NSApplication.shared.keyWindow?.styleMask.contains(.fullScreen) == true {
                    NSApplication.shared.keyWindow?.toggleFullScreen(nil)
                }
                return .handled
            })
            // Shift+Arrow for 10-move jumps
            .onKeyPress(phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    switch press.key {
                    case .leftArrow:
                        print("⌨️ Shift+Left arrow pressed (10 moves)")
                        for _ in 0..<10 {
                            guard boardVM.currentMoveIndex > 0 else { break }
                            boardVM.previousMove()
                        }
                        return .handled
                    case .rightArrow:
                        print("⌨️ Shift+Right arrow pressed (10 moves)")
                        for _ in 0..<10 {
                            guard boardVM.currentMoveIndex < boardVM.totalMoves else { break }
                            boardVM.nextMove()
                        }
                        return .handled
                    default:
                        return .ignored
                    }
                }
                return .ignored
            }
    }
}

/// Extension to make keyboard shortcuts easy to apply
extension View {
    func keyboardShortcuts(boardVM: BoardViewModel) -> some View {
        modifier(KeyboardShortcutsModifier(boardVM: boardVM))
    }
}
