import SwiftUI

/// Applied to an available next step, never to a destructive shortcut or a disabled control.
enum ActionAttention {case none,checking,required
    var color:Color {self == .required ? .red:self == .checking ? .orange:.clear}
}
private struct ActionAttentionModifier:ViewModifier {
    let attention:ActionAttention
    @Environment(\.isEnabled) private var enabled
    func body(content:Content)->some View {
        content
            .background((enabled ? attention.color:Color.clear).opacity(0.15),in:RoundedRectangle(cornerRadius:6))
            .overlay(RoundedRectangle(cornerRadius:6).stroke(enabled ? attention.color:.clear,lineWidth:2).allowsHitTesting(false))
    }
}
extension View {
    func actionAttention(_ attention:ActionAttention)->some View {modifier(ActionAttentionModifier(attention:attention))}
}
