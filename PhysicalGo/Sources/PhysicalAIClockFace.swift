import SwiftUI

/// Presentation only. The AI timing owner supplies the elapsed time and running
/// side; pending physical placement must never decide which clock is highlighted.
struct PhysicalAIClockFace:View {
    let black:Bool
    let human:Bool
    let time:String
    let selected:Bool
    let running:Bool
    let finished:Bool
    var large=false
    private var state:String {finished ? "FINAL":selected ? (running ? "RUNNING":"PAUSED"):"Waiting"}
    var body:some View {
        VStack(alignment:.leading,spacing:large ? 12:4) {
            HStack {
                Circle().fill(black ? Color.black:Color.white)
                    .overlay(Circle().stroke(.gray,lineWidth:1)).frame(width:22,height:22)
                    .accessibilityHidden(true)
                Text("\(black ? "Black":"White") · \(human ? "You":"KataGo")")
                    .font(.system(size:large ? 28:17,weight:.semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength:4)
                Text(state).font(large ? .headline:.caption.weight(.semibold))
            }
            Text(time).font(.system(size:large ? 180:68,weight:.bold,design:.rounded))
                .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
            Text("Elapsed time").font(.system(size:large ? 28:14,weight:.medium))
                .foregroundStyle(.secondary)
        }.padding(large ? 24:10).frame(maxWidth:.infinity,alignment:.leading)
            .background(selected && !finished ? Color.accentColor.opacity(0.15):Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(selected && !finished ? Color.accentColor:Color.clear,lineWidth:3))
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(black ? "Black":"White"), \(human ? "you":"KataGo"). Elapsed time \(time). \(state).")
    }
}
