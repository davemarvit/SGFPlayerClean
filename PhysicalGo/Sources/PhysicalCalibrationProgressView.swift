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
                    Label(progress.workflowTitle,systemImage:"scope")
                        .font(.headline)
                    Text(title(progress,interrupted:interrupted)).font(.callout)
                    if progress.total>0 {
                        ProgressView(value:Double(progress.completed),total:Double(progress.total))
                            .accessibilityLabel(progress.workflowTitle)
                            .accessibilityValue("\(progress.completed) of \(progress.total) complete")
                        Text(progress.countSummary)
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
        case "seed_ready":return "Three-point seed collected — setup review still required"
        case "feedback_checked":return "Feedback targets reached — gameplay review still required"
        case "off_unconfirmed":return "Calibration stopped — pointer shutdown is unconfirmed"
        case "stopped":return "Calibration stopped before approval"
        default:return p.stageTitle
        }
    }
    private func detail(_ p:PhysicalCalibrationProgress,interrupted:Bool)->String {
        if interrupted {return "Showing the last reported progress. Completion and pointer state are unknown; check calibration before play."}
        switch p.state {
        case "candidate_ready":return "All point checks finished. The new laser map still needs review and activation before play."
        case "spot_verified":return "Only the current spot was checked. This does not approve a setup for play."
        case "seed_ready":return "Three observations were collected for the initial response estimate. This does not activate laser gameplay. Keep the saved measurements for setup review."
        case "feedback_checked":return "This run reached its listed targets using measured corrections. It does not activate gameplay or represent a complete game test."
        case "off_unconfirmed":return "Check the pointer before approaching it. This run has not approved the setup for play."
        case "stopped":return "The setup has not been approved for play. Resolve the reported calibration issue before trying again."
        default:
            if p.mode == "three_point_seed" {return "Keep the board clear. The bar counts selected observations; transit images are excluded. Elapsed time is measured, not an estimate of time remaining."}
            return "Keep the board clear. The bar counts completed point checks, not remaining time; individual points may need several corrections."
        }
    }
}
