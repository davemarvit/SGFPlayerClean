// MARK: - File: KeyboardShortcuts.swift (v5.100)
import SwiftUI

struct KeyboardShortcutsModifier: ViewModifier {
    let boardVM: BoardViewModel
    func body(content: Content) -> some View {
        content.focusable().onKeyPress(phases: .down) { press in
            let isShift = press.modifiers.contains(.shift)
            switch press.key {
            case .leftArrow: isShift ? boardVM.stepBackwardTen() : boardVM.stepBackward(); return .handled
            case .rightArrow: isShift ? boardVM.stepForwardTen() : boardVM.stepForward(); return .handled
            case .upArrow: boardVM.goToStart(); return .handled
            case .downArrow: boardVM.goToEnd(); return .handled
            case .space: boardVM.toggleAutoPlay(); return .handled
            default: return .ignored
            }
        }
    }
}
extension View { func keyboardShortcuts(boardVM: BoardViewModel) -> some View { modifier(KeyboardShortcutsModifier(boardVM: boardVM)) } }
