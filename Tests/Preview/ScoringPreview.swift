import SwiftUI
import AppKit

@main
struct ScoringPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let sample = OGSScoreSummary.parse([
            "black": ["total": 29, "territory": 25, "stones": 0, "prisoners": 4, "komi": 0, "handicap": 0],
            "white": ["total": 35.5, "territory": 25, "stones": 0, "prisoners": 4, "komi": 6.5, "handicap": 0]
        ])!
        let content = VStack(alignment: .leading, spacing: 18) {
            Text("SGF Player · scoring preview").font(.title2.bold())
            Text("Offline sample states — no OGS connection or game actions.").foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                fixture("1 · Review", acceptance: .none)
                fixture("2 · Awaiting confirmation", acceptance: .submitting)
                VStack(alignment: .leading, spacing: 12) {
                    Text("3 · Finished (sample scores)").font(.subheadline.bold())
                    OGSScoringPanel(finished: true, connected: true, participant: true, atLivePosition: true,
                        canEdit: false, acceptance: .none, strictSeki: false, summary: sample,
                        winnerDescription: sample.winnerDescription(blackName: "Dave", whiteName: "Alice"), error: nil,
                        accept: {}, resume: {})
                }.frame(width: 330)
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        .frame(width: 1078)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("Could not render scoring preview")
        }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }

    @MainActor static func fixture(_ title: String, acceptance: OGSScoreAcceptance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.bold())
            OGSScoringPanel(finished: false, connected: true, participant: true, atLivePosition: true,
                canEdit: true, acceptance: acceptance, strictSeki: false, summary: nil, error: nil,
                accept: {}, resume: {})
        }.frame(width: 330)
    }
}
