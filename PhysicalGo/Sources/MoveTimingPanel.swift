import SwiftUI
import AppKit

@MainActor final class MoveTimingReportStore:ObservableObject {
    @Published private(set) var reports=[MoveTimingReport]()
    @Published private(set) var error:String?
    @Published private(set) var loading=false
    private let queue=DispatchQueue(label:"PhysicalGo.timing-reports",qos:.utility)
    private let reader:MoveTimingReportReader
    init() {
        reader=MoveTimingReportReader(onlineRoot:PhysicalSGFExport.directory.appendingPathComponent("Move Timing"),localRoot:GameRecorder.recordingsDirectory)
    }
    func refresh() {
        guard !loading else {return};loading=true
        let reader=self.reader
        queue.async { [weak self] in
            let result=Result {try reader.refresh()}
            DispatchQueue.main.async {
                guard let self else {return};self.loading=false
                switch result {
                case .success(let reports):self.reports=reports;self.error=nil
                case .failure(let error):self.error="Could not read timing history: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct MoveTimingPanel:View {
    let mode:PhysicalPlayMode
    @ObservedObject var recorder:GameRecorder
    let quarterTurns:Int
    @StateObject private var store=MoveTimingReportStore()
    @State private var selection=""
    private var reports:[MoveTimingReport] {store.reports.filter {$0.mode==mode.rawValue}}
    private var selected:MoveTimingReport? {
        if let report=reports.first(where:{$0.id==selection}) {return report}
        if mode == .local,let url=recorder.autosaveURL,
           let report=reports.first(where:{$0.id==url.deletingPathExtension().appendingPathExtension("observations.jsonl").resolvingSymlinksInPath().path}) {return report}
        return reports.first
    }
    private func seconds(_ value:Double?)->String {value.map {String(format:"%.2f s",$0)} ?? "—"}
    private func coordinate(_ point:Int?,size:Int)->String {
        guard let point,(0..<(size*size)).contains(point),[9,13,19].contains(size) else {return "—"}
        let displayed=mode == .local ? PhysicalMoveInference.displayedPoint(row:point/size,col:point%size,size:size,quarterTurns:quarterTurns) : point
        return "\(Array("ABCDEFGHJKLMNOPQRST")[displayed%size])\(size-displayed/size)"
    }
    var body:some View {
        GroupBox {
            VStack(alignment:.leading,spacing:9) {
                HStack {
                    Text("Move timing").font(.headline)
                    Spacer()
                    Button("Refresh") {store.refresh()}.disabled(store.loading)
                }
                Text(mode == .online ? "First candidate → sent to SGF Player" : "First retained candidate → recorded")
                    .font(.subheadline.weight(.semibold))
                Text("Confirmation delay, not physical placement time or CPU processing time. Saved history reloads after restarting.")
                    .font(.caption).foregroundStyle(.secondary)
                if !reports.isEmpty {
                    Picker("Game",selection:Binding(get:{selected?.id ?? ""},set:{selection=$0})) {
                        ForEach(reports) {report in
                            Text("\(report.title) · \(Date(timeIntervalSince1970:report.time).formatted(date:.abbreviated,time:.shortened))").tag(report.id)
                        }
                    }
                }
                if let report=selected {
                    summary(report)
                    DisclosureGroup("Individual moves (\(report.samples.count))") {
                        ScrollView {
                            LazyVStack(alignment:.leading,spacing:8) {
                                ForEach(report.samples) {sample in
                                    VStack(alignment:.leading,spacing:2) {
                                        HStack {
                                            Text("\(sample.number.map {"\($0) · "} ?? "")\(sample.color.capitalized) \(coordinate(sample.point,size:sample.size))")
                                            Spacer();Text(seconds(sample.seconds)).monospacedDigit()
                                        }
                                        if let unavailable=sample.unavailable {Text(unavailable).font(.caption).foregroundStyle(.secondary)}
                                        if let server=sample.serverSeconds {Text("Send → server observed: \(seconds(server))").font(.caption).foregroundStyle(.secondary)}
                                    }.foregroundStyle((sample.seconds ?? 0)>=5 ? Color.orange:Color.primary)
                                }
                            }.padding(.trailing,8)
                        }.frame(height:200)
                    }
                    if !report.reviews.isEmpty {
                        DisclosureGroup("Slow / uncertain events (\(report.reviews.count))") {
                            ScrollView {
                                LazyVStack(alignment:.leading,spacing:8) {
                                    ForEach(report.reviews) {review in
                                        HStack {
                                            Text("\(coordinate(review.point,size:review.size)) · \(review.reason)").font(.caption)
                                            Spacer()
                                            if let folder=review.folder {
                                                Button("Show clip") {NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:folder)])}
                                            } else {Text("No clip saved").font(.caption).foregroundStyle(.secondary)}
                                        }
                                    }
                                }
                            }.frame(height:150)
                        }
                    }
                    Button("Show timing files") {NSWorkspace.shared.activateFileViewerSelecting(report.files)}
                } else {
                    Text(store.loading ? "Loading saved timings…" : "No timing records yet for this mode. Timings appear as camera moves are confirmed.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let error=store.error {Text(error).foregroundStyle(.red)}
            }.frame(maxWidth:.infinity,alignment:.leading).padding(4)
        }
        .onChange(of:mode) {_,_ in selection=""}
        .task {
            while !Task.isCancelled {
                store.refresh()
                do {try await Task.sleep(nanoseconds:3_000_000_000)} catch {return}
            }
        }
    }
    @ViewBuilder private func summary(_ report:MoveTimingReport)->some View {
        let values=report.values
        if values.isEmpty {
            Text("No measured confirmation delays in this game. Older local recordings, manual moves, passes and interrupted measurements are excluded.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("\(values.count) timed moves · Average \(seconds(report.average)) · Median \(seconds(report.percentile(0.5)))")
                .monospacedDigit()
            Text("95th percentile \(seconds(report.percentile(0.95))) · Longest \(seconds(values.last))").monospacedDigit()
            let bins=report.bins,labels=["<1 s","1–2 s","2–3 s","3–5 s","≥5 s"]
            ForEach(0..<5,id:\.self) {index in
                HStack(spacing:8) {
                    Text(labels[index]).frame(width:48,alignment:.leading)
                    ProgressView(value:Double(bins[index]),total:Double(max(1,bins.max() ?? 1)))
                        .tint(index==4 ? .orange:.teal)
                    Text("\(bins[index]) · \(Int((Double(bins[index])*100/Double(values.count)).rounded()))%")
                        .monospacedDigit().frame(width:80,alignment:.trailing)
                }.font(.caption)
            }
            let estimates=report.samples.filter { $0.unavailable?.hasPrefix("Estimate") == true }.count
            if estimates>0 {Text("\(estimates) durations estimated from older candidate-observation logs.").font(.caption).foregroundStyle(.secondary)}
            if report.samples.count>values.count {Text("\(report.samples.count-values.count) moves lack a comparable duration and are excluded.").font(.caption).foregroundStyle(.secondary)}
        }
    }
}
