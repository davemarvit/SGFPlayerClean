import SwiftUI

struct TabletEvaluationView: View {
    @ObservedObject var game: TabletGame
    @ObservedObject var analysis: TabletAnalysis
    @State private var minimumLoss = 2.0
    var body: some View {
        let values = analysis.evaluations(game.tree)
        VStack(alignment: .leading, spacing: 8) {
            Text("Game coverage: \(values.count) / \(game.tree.activePath.count) positions").font(.caption)
            if !values.isEmpty {
                Text("Black win chance").font(.caption)
                GeometryReader { geometry in
                    Path { path in
                        var connected = false
                        for id in game.tree.activePath {
                            guard let value = values.first(where: { $0.id == id }),
                                  let index = game.tree.activePath.firstIndex(of: id) else { connected = false; continue }
                            let point = CGPoint(x: geometry.size.width * Double(index) / Double(max(1, game.tree.activePath.count - 1)), y: geometry.size.height * (1 - value.winrate))
                            if connected { path.addLine(to: point) } else { path.move(to: point) }
                            connected = true
                        }
                    }.stroke(.cyan, lineWidth: 2)
                }.frame(height: 70).background(.white.opacity(0.05))
                    .accessibilityLabel("Win chance across analyzed positions")
                Picker("Minimum mistake loss", selection: $minimumLoss) {
                    Text("2 points").tag(2.0); Text("5 points").tag(5.0); Text("10 points").tag(10.0)
                }.font(.caption)
                HStack {
                    Button("Previous mistake") { navigate(values, direction: -1) }
                    Button("Next mistake") { navigate(values, direction: 1) }
                }.font(.caption).frame(minHeight: 44)
            }
        }
    }
    private func navigate(_ values: [(id: Int, score: Double, winrate: Double)], direction: Int) {
        let path = game.tree.activePath
        let selected = path.firstIndex(of: game.tree.selectedID) ?? 0
        let candidates = path.indices.dropLast().filter { index in
            guard let before = values.first(where: { $0.id == path[index] }),
                  let after = values.first(where: { $0.id == path[index + 1] }),
                  let color = game.tree.nodes[path[index + 1]].color else { return false }
            let loss = color == .black ? before.score - after.score : after.score - before.score
            return loss >= minimumLoss && (direction > 0 ? index > selected : index < selected)
        }
        if let index = direction > 0 ? candidates.first : candidates.last { game.select(path[index]) }
    }
}

struct TabletLibrary: View {
    @ObservedObject var game: TabletGame
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var importing = false
    var body: some View {
        NavigationStack {
            List {
                Button("Import from Files…") { importing = true }.frame(minHeight: 44)
                if files.isEmpty { Text("Saved games appear here. Import an SGF from Files to review it.").foregroundStyle(.secondary) }
                ForEach(files, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) { game.open(url); dismiss() }
                        .frame(minHeight: 44)
                }
            }.navigationTitle("Game library")
                .toolbar { Button("Done") { dismiss() } }
                .onAppear {
                    let folder = URL.documentsDirectory.appendingPathComponent("Saved Games", isDirectory: true)
                    files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                        .filter { $0.pathExtension.lowercased() == "sgf" }
                        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.sgf, .plainText, .data]) { result in
                    switch result {
                    case .success(let url): game.open(url); dismiss()
                    case .failure(let error): game.error = error.localizedDescription
                    }
                }
        }
    }
}
