import SwiftUI

struct PhysicalCalibrationProgressView:View {
    @State private var reader=PhysicalCalibrationProgressReader()
    @State private var now=Date().timeIntervalSince1970
    private func duration(_ seconds:Double)->String {
        let seconds=Int(max(0,seconds))
        return seconds<60 ? "\(seconds)s" : "\(seconds/60)m \(seconds%60)s"
    }
    var body:some View {
        Group {
            if let progress=reader.latest {
                let interrupted=reader.interrupted(now:now)
                VStack(alignment:.leading,spacing:7) {
                    Label(progress.mode == "spot_check" ? "Laser spot check":"Initial laser calibration",systemImage:"scope")
                        .font(.headline)
                    Text(title(progress,interrupted:interrupted)).font(.callout)
                    if progress.total>0 {
                        ProgressView(value:Double(progress.completed),total:Double(progress.total))
                            .accessibilityLabel("Calibration point checks")
                            .accessibilityValue("\(progress.completed) of \(progress.total) complete")
                        Text("\(progress.completed) of \(progress.total) point checks complete · \(progress.fitCompleted)/\(progress.fitTotal) calibration, \(progress.validationCompleted)/\(progress.validationTotal) accuracy checks")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Elapsed \(duration(progress.elapsedSeconds))"+(progress.running && !interrupted ? " · This stage \(duration(progress.stageElapsedSeconds))":""))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(detail(progress,interrupted:interrupted)).font(.caption).foregroundStyle(.secondary)
                    if !progress.running || interrupted {
                        Text("Last update \(Date(timeIntervalSince1970:progress.updatedAtUnix).formatted(date:.abbreviated,time:.shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.quaternary,in:RoundedRectangle(cornerRadius:8))
            }
        }
        .task {
            while !Task.isCancelled {
                let data=await Task.detached(priority:.utility) {
                    PhysicalCalibrationProgressReader.read(PhysicalCalibrationProgressReader.url)
                }.value
                guard !Task.isCancelled else {return}
                now=Date().timeIntervalSince1970
                reader.accept(data,now:now)
                do {try await Task.sleep(nanoseconds:500_000_000)} catch {return}
            }
        }
    }
    private func title(_ p:PhysicalCalibrationProgress,interrupted:Bool)->String {
        if interrupted {return "Progress updates unavailable"}
        switch p.state {
        case "candidate_ready":return "Measurements complete — setup review still required"
        case "spot_verified":return "Spot check complete"
        case "off_unconfirmed":return "Calibration stopped — pointer shutdown is unconfirmed"
        case "stopped":return "Calibration stopped before approval"
        default:return p.stageTitle
        }
    }
    private func detail(_ p:PhysicalCalibrationProgress,interrupted:Bool)->String {
        if interrupted {return "Showing the last reported progress. Completion and pointer state are unknown; check calibration before play."}
        switch p.state {
        case "candidate_ready":return "All point checks finished. The new laser map still needs review and activation before play."
        case "spot_verified":return "Only the current spot was checked. Full board calibration is still needed."
        case "off_unconfirmed":return "Check the pointer before approaching it. This run has not approved the setup for play."
        case "stopped":return "The setup has not been approved for play. Resolve the reported calibration issue before trying again."
        default:return "Keep the board clear. The bar counts completed point checks, not remaining time; individual points may need several corrections."
        }
    }
}
