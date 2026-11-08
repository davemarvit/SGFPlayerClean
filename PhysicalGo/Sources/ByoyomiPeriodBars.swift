import SwiftUI

/// Fixed slots keep surviving periods the same size and position as others expire.
struct ByoyomiPeriodProgress {
    let capacity:Int
    let fractions:[Double]
    init(settings:LocalClockSettings,side:LocalClockEngine.Side) {
        capacity=max(1,min(100,settings.periods))
        let count=max(0,min(capacity,side.periods))
        let remaining=side.remaining.isFinite ? max(0,side.remaining):0
        let fraction=side.overtime ? min(1,remaining/Double(max(1,settings.periodSeconds))):1
        fractions=(0..<count).compactMap {index in
            let value=index==count-1 ? fraction:1
            return value>0 ? value:nil
        }
    }
    var columns:Int {min(10,capacity)}
    var rows:Int {(capacity+columns-1)/columns}
}

struct ByoyomiPeriodBars:View {
    let settings:LocalClockSettings
    let side:LocalClockEngine.Side
    let active:Bool
    var large=false
    private var progress:ByoyomiPeriodProgress {ByoyomiPeriodProgress(settings:settings,side:side)}
    private var description:String {
        let count=progress.fractions.count
        guard count>0 else {return "No periods left"}
        if !side.overtime {return "\(count) full periods available after main time"}
        let periods=count==1 ? "Final period":"\(count) periods left"
        return "\(periods). \(LocalClockEngine.display(side.remaining)) remaining in the current \(settings.periodSeconds)-second period."
    }
    var body:some View {
        let progress=progress,height:CGFloat=large ? 24:18,gap:CGFloat=large ? 12:10
        Canvas {context,size in
            let width=max(0,(size.width-CGFloat(progress.columns-1)*gap)/CGFloat(progress.columns))
            for (index,fraction) in progress.fractions.enumerated() {
                let current=side.overtime && index==progress.fractions.count-1
                let emphasized=current && active
                let color:Color=emphasized ? (side.remaining<=10 ? .red:.accentColor):.primary
                let rect=CGRect(x:CGFloat(index%progress.columns)*(width+gap),y:CGFloat(index/progress.columns)*(height+gap),
                                width:min(width,max(1.6,width*CGFloat(fraction))),height:height)
                let path=RoundedRectangle(cornerRadius:min(3,rect.width/2)).path(in:rect.insetBy(dx:0.8,dy:0.8))
                context.fill(path,with:.color(color.opacity(emphasized ? 0.28:side.overtime ? 0.10:0.05)))
                context.stroke(path,with:.color(color.opacity(emphasized ? 1:side.overtime ? 0.70:0.35)),lineWidth:1.6)
            }
        }
        .frame(height:CGFloat(progress.rows)*height+CGFloat(progress.rows-1)*gap)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Byoyomi periods")
        .accessibilityValue(description)
        .help("The last visible bar is the current period. It shrinks with the clock, refills after an on-time move, and disappears when exhausted. Earlier bars are unused periods.")
    }
}
