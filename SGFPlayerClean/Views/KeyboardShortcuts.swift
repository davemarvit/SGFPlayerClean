// MARK: - File: KeyboardShortcuts.swift (v5.100)
import SwiftUI

struct KeyboardShortcutsModifier: ViewModifier {
    let boardVM: BoardViewModel
    @ObservedObject var appModel: AppModel
    
    func body(content: Content) -> some View {
        // FIX: Use default phase (.up) so TextFields (Leaf nodes) consume keys first.
        // Using .down (tunneling) was hijacking inputs before the UI could see them.
        content.focusable().onKeyPress { press in
            // CRITICAL: If user is typing in chat, IGNORE all shortcuts.
            guard !appModel.isTypingInChat else { return .ignored }
            
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
extension View { func keyboardShortcuts(boardVM: BoardViewModel, appModel: AppModel) -> some View { modifier(KeyboardShortcutsModifier(boardVM: boardVM, appModel: appModel)) } }
