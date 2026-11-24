import SwiftUI

struct PhysicalAIMoveClickControls:View {
    @ObservedObject var click:PhysicalAIMoveClick
    private var percentage:String {"\(Int((click.volume*100).rounded()))%"}
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            Toggle("Stone click when the AI laser first appears",isOn:$click.enabled)
            HStack(spacing:8) {
                Text("Click volume")
                Slider(value:$click.volume,in:0...1)
                    .frame(maxWidth:200).accessibilityLabel("AI stone click volume").accessibilityValue(percentage)
                Text(percentage).monospacedDigit().frame(width:36,alignment:.trailing)
                Button("Test click") {click.preview()}.disabled(!click.enabled || click.volume<=0)
                    .help("Play the sound without activating the laser or changing the game.")
            }.disabled(!click.enabled)
            Text("Once per AI move, through your Mac’s selected audio output. Independent of warning sounds and clock volume.")
                .font(.caption).foregroundStyle(.secondary)
            if click.enabled,click.volume==0 {Text("Stone click is muted at 0% volume.").font(.caption).foregroundStyle(.secondary)}
            if let status=click.status {Text(status).font(.caption).foregroundStyle(.secondary)}
        }
    }
}
