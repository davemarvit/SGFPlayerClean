import SwiftUI
import AppKit

struct PhysicalScoreApprovals:View {
    @ObservedObject var scoring:PhysicalScoring
    @State var expanded=false
    @State private var editing:PhysicalScoring.Approval?
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            ScoreApprovalCheckbox(checked:scoring.allApproved,mixed:scoring.partlyApproved,
                enabled:!scoring.busy && scoring.aiAvailable && !scoring.accepted) {scoring.approveAll(!scoring.allApproved)}
                .frame(height:22)
            DisclosureGroup("Review components",isExpanded:$expanded) {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(scoring.requiredApprovals,id:\.self) {component in
                        HStack(alignment:.top,spacing:8) {
                            Toggle(isOn:Binding(get:{scoring.approvedComponents.contains(component)},set:{scoring.setApproval(component,to:$0)})) {
                                VStack(alignment:.leading,spacing:2) {
                                    Text(component.rawValue)
                                    Text(detail(component)).font(.caption).foregroundStyle(.secondary)
                                }
                            }.disabled(scoring.busy || !scoring.aiAvailable || scoring.accepted)
                            Spacer(minLength:0)
                            Button("Edit") {
                                editing=component
                                switch component {
                                case .deadGroups:scoring.markingTool = .deadGroups
                                case .territory:scoring.markingTool = .blackTerritory
                                case .neutral:scoring.markingTool = .neutral
                                case .prisoners:break
                                }
                            }.buttonStyle(.borderless).accessibilityLabel("Edit \(component.rawValue.lowercased())")
                                .disabled(scoring.busy || scoring.accepted)
                        }
                        if editing==component {editor(component)}
                    }
                }.padding(.leading,16).padding(.top,8)
            }
        }.fixedSize(horizontal:false,vertical:true)
    }
    private func detail(_ component:PhysicalScoring.Approval)->String {
        guard let s=scoring.session else {return ""}
        switch component {
        case .prisoners:return "Black \(s.capturesByBlack) · White \(s.capturesByWhite)"
        case .deadGroups:return "Black \(s.deadStones.filter {s.board.stones[$0] == .black}.count) · White \(s.deadStones.filter {s.board.stones[$0] == .white}.count)"
        case .territory:return "Black \(scoring.countedResult?.black.territory ?? 0) · White \(scoring.countedResult?.white.territory ?? 0)"
        case .neutral:return "\(scoring.unassignedEmptyPoints) empty points not counted"
        }
    }
    @ViewBuilder private func editor(_ component:PhysicalScoring.Approval)->some View {
        VStack(alignment:.leading,spacing:6) {
            switch component {
            case .prisoners:
                Text("Enter prisoners already removed from the board. Dead stones still on the board are counted separately.").font(.caption)
                Stepper("Black holds \(scoring.session?.capturesByBlack ?? 0)",value:Binding(get:{scoring.session?.capturesByBlack ?? 0},set:{scoring.setPrisoners(black:$0,white:scoring.session?.capturesByWhite ?? 0)}),in:0...10000)
                Stepper("White holds \(scoring.session?.capturesByWhite ?? 0)",value:Binding(get:{scoring.session?.capturesByWhite ?? 0},set:{scoring.setPrisoners(black:scoring.session?.capturesByBlack ?? 0,white:$0)}),in:0...10000)
            case .deadGroups:
                Text("Click a stone on the board to mark its whole group alive or dead.")
            case .territory:
                Picker("Assign territory",selection:$scoring.markingTool) {
                    Text("Black").tag(PhysicalScoring.MarkingTool.blackTerritory)
                    Text("White").tag(PhysicalScoring.MarkingTool.whiteTerritory)
                }.pickerStyle(.segmented)
                Text("Click an empty point or a marked-dead stone on the board to assign it.")
            case .neutral:
                Text("Click a point on the board to leave it neutral and uncounted. To award a point instead, edit Territory assignments.")
            }
        }.font(.callout).padding(.leading,20).disabled(scoring.busy || scoring.accepted)
    }
}

/// Native mixed-state checkbox: clicking a partial selection approves all,
/// clicking a fully checked selection clears all. The model is platform independent.
struct ScoreApprovalCheckbox:NSViewRepresentable {
    let checked:Bool
    let mixed:Bool
    let enabled:Bool
    let action:()->Void
    func makeCoordinator()->Coordinator {Coordinator(action)}
    func makeNSView(context:Context)->NSButton {
        let button=NSButton(checkboxWithTitle:"Approve all scoring details",target:context.coordinator,action:#selector(Coordinator.press))
        button.allowsMixedState=true
        button.setContentHuggingPriority(.defaultHigh,for:.horizontal)
        return button
    }
    func updateNSView(_ button:NSButton,context:Context) {
        context.coordinator.action=action
        button.state=checked ? .on:mixed ? .mixed:.off
        button.isEnabled=enabled
    }
    final class Coordinator:NSObject {
        var action:()->Void
        init(_ action:@escaping ()->Void) {self.action=action}
        @objc func press() {action()}
    }
}
