import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

extension UTType { static let sgf = UTType(importedAs: "org.red-bean.sgf", conformingTo: .plainText) }
struct SGFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sgf, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

enum TabletMode: String, CaseIterable, Codable {
    case playOnline = "Play Online", localPlay = "Local Play", observe = "Observe", review = "Review"
    var identifier: String {
        switch self {
        case .playOnline: return "onlineMode"
        case .localPlay: return "localMode"
        case .observe: return "observeMode"
        case .review: return "reviewMode"
        }
    }
}

@MainActor final class TabletGame: ObservableObject {
    let player = SGFPlayer()
    @Published var isOnline = false
    @Published private(set) var localMode: TabletMode = .localPlay
    var mode: TabletMode {
        guard isOnline, let online else { return localMode }
        let observing = online.showLobby ? online.browsingObservedGames : online.client.observationOnly
        return observing ? .observe : .playOnline
    }
    func selectLocalMode(_ mode: TabletMode) {
        guard mode == .localPlay || mode == .review else { return }
        leaveOnline()
        localMode = mode
        persist()
    }
    @Published var online: TabletOnline?
    private var localBeforeOnline: SGFPlayer.LocalGameSnapshot?
    private var localTitle: String?
    var canAnalyze: Bool { AppSettings.shared.analysisEnabled && !isOnline && online?.client.hasOngoingAccountGame != true }
    var deadStones: Set<BoardPosition> { isOnline ? (online?.deadStones ?? []) : (scoring?.deadStones ?? []) }
    var territory: [BoardPosition: Stone] { isOnline ? (online?.territory ?? [:]) : (scoring?.territory ?? [:]) }
    func startOnline(client: OGSClient? = nil, observing: Bool = false) {
        guard !isOnline else { online?.browse(observing: observing); return }
        persist()
        localBeforeOnline = player.createSnapshot(); localTitle = title
        scoring = nil; selectedPoint = nil; player.pause()
        player.load(game: SGFGame()); title = "Online play"; isOnline = true
        if online == nil { online = TabletOnline(game: self, client: client ?? OGSClient()) }
        online?.start(observing: observing); positionID = UUID()
    }
    func leaveOnline() {
        guard isOnline else { return }
        online?.leave(); isOnline = false
        if let snapshot = localBeforeOnline { player.restoreSnapshot(snapshot) }
        title = localTitle ?? "Local game"; selectedPoint = nil
        localBeforeOnline = nil; localTitle = nil; persist()
    }
    @Published var tree: ReviewTree
    @Published var selectedPoint: BoardPosition?
    @Published var error: String?
    @Published var scoring: LocalScoringSession?
    @Published var positionID = UUID()
    @Published var title = "Local game"
    private var stoneAudio: AVAudioPlayer?
    private let saveURL: URL?
    private let archiveDirectory: URL?
    private struct Saved: Codable { let sgf: String; let node: Int; let title: String; let mode: TabletMode? }
    init(restore: Bool = true, storageDirectory: URL? = nil) {
        saveURL = restore ? (storageDirectory ?? URL.applicationSupportDirectory).appendingPathComponent("TabletGame.json") : nil
        archiveDirectory = restore ? (storageDirectory ?? URL.documentsDirectory).appendingPathComponent("Saved Games", isDirectory: true) : nil
        var game = SGFGame(); game.info.rules = "Japanese"; game.info.komi = "6.5"
        tree = ReviewTree(game: game, analysisID: UUID().uuidString, filename: "Local game.sgf")
        player.load(game: game)
        if let saveURL, FileManager.default.fileExists(atPath: saveURL.path) {
            do {
                let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: saveURL))
                try load(text: saved.sgf, name: saved.title, save: false)
                select(saved.node, save: false)
                localMode = saved.mode == .review ? .review : .localPlay
            } catch { self.error = "The saved session could not be restored: \(error.localizedDescription)" }
        }
    }
    var exportedSGF: String { SGFWriter.serialize(tree.source) }
    var currentNode: ReviewTree.Node { tree.nodes[tree.selectedID] }
    var pointLabel: String {
        guard let p = selectedPoint else { return "Tap an intersection" }
        let letters = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")
        return "\(letters[p.col])\(player.board.size - p.row)"
    }
    func newGame(size: Int) {
        guard !isOnline else { return }
        do { try archiveCurrentGame() } catch { self.error = "Could not preserve the current game: \(error.localizedDescription)"; return }
        var game = SGFGame(); game.boardSize = size; game.info.rules = "Japanese"; game.info.komi = "6.5"
        tree = ReviewTree(game: game, analysisID: UUID().uuidString, filename: "Local game.sgf")
        localMode = .localPlay
        title = "Local game"; scoring = nil; selectedPoint = nil; player.pause(); player.load(game: game); persist()
    }
    func load(text: String, name: String, save: Bool = true) throws {
        guard !isOnline else { throw SGFError.parseError("Return to local play before opening an SGF.") }
        guard text.utf8.count <= 10_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let source = try SGFParser.parse(text: text)
        let game = SGFGame.from(tree: source)
        guard (2...25).contains(game.boardSize) else { throw SGFError.parseError("Supported board sizes are 2–25.") }
        var candidate = ReviewTree(game: game, analysisID: UUID().uuidString, filename: name, originalSGF: text)
        candidate.select(0)
        let playback = try candidate.playbackGame()
        if save { try archiveCurrentGame() }
        player.pause(); player.load(game: playback); tree = candidate
        localMode = .review
        title = name; selectedPoint = nil; scoring = nil
        if save { persist() }
    }
    func open(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10_000_000 else { throw CocoaError(.fileReadTooLarge) }
            try load(text: String(contentsOf: url, encoding: .utf8), name: url.deletingPathExtension().lastPathComponent)
        } catch { self.error = "Could not open this SGF: \(error.localizedDescription)" }
    }
    func select(_ id: Int, save: Bool = true) {
        guard !isOnline else { return }
        var candidate = tree; candidate.select(id)
        do {
            let game = try candidate.playbackGame()
            player.pause(); player.load(game: game); player.seek(to: candidate.nodes[candidate.selectedID].moveNumber)
            tree = candidate; selectedPoint = nil; scoring = nil
            if save { persist() }
        } catch { self.error = error.localizedDescription }
    }
    func step(_ direction: Int) { if let id = tree.neighbor(direction: direction) { select(id) } }
    /// A completed board tap places exactly one legal stone, or edits scoring marks.
    func tap(at point: BoardPosition) {
        selectedPoint = nil
        pick(point)
        guard selectedPoint == point else { return }
        play()
    }
    func pick(_ point: BoardPosition) {
        if isOnline { online?.pick(point); return }
        if scoring != nil {
            if scoring?.tool == .deadGroups { scoring?.toggleDeadGroup(at: point) }
            else { scoring?.toggleNeutralArea(at: point) }
            return
        }
        guard player.moveRejection(color: player.turn, x: point.col, y: point.row) == nil else { selectedPoint = nil; return }
        selectedPoint = point
    }
    func play(pass: Bool = false) {
        if isOnline { online?.play(pass: pass); return }
        guard scoring == nil, pass || selectedPoint != nil else { return }
        let point = pass ? nil : selectedPoint
        guard player.moveRejection(color: player.turn, x: point?.col ?? -1, y: point?.row ?? -1) == nil else { return }
        let updated = tree.addingMove(color: player.turn, point: point)
        do {
            let playback = try updated.playbackGame()
            player.load(game: playback); player.seek(to: updated.nodes[updated.selectedID].moveNumber)
            tree = updated; selectedPoint = nil
            if pass { SoundManager.shared.play("pass") }
            else if !AppSettings.shared.soundIsSilent {
                if stoneAudio == nil, let url = Bundle.main.url(forResource: "Stone_click_1", withExtension: "mp3") { stoneAudio = try? AVAudioPlayer(contentsOf: url) }
                stoneAudio?.currentTime = 0
                stoneAudio?.volume = Float(AppSettings.shared.effectiveStoneVolume)
                stoneAudio?.play()
            }
            persist()
        } catch { self.error = error.localizedDescription }
    }
    func beginScoring() { guard !isOnline else { return }; selectedPoint = nil; scoring = LocalScoringSession(player: player, handicap: tree.baseGame.handicap) }
    private func archiveCurrentGame() throws {
        guard let archiveDirectory, tree.nodes.count > 1 || title != "Local game" || !player.board.stones.isEmpty else { return }
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let safeName = title.map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : "_" }
        let filename = String(safeName.prefix(80)) + "-" + UUID().uuidString.prefix(8) + ".sgf"
        try Data(exportedSGF.utf8).write(to: archiveDirectory.appendingPathComponent(filename), options: .atomic)
    }
    func persist() {
        positionID = UUID()
        guard !isOnline, let saveURL else { return }
        do {
            try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(sgf: exportedSGF, node: tree.selectedID, title: title, mode: localMode)).write(to: saveURL, options: .atomic)
        } catch { self.error = "Could not save this session: \(error.localizedDescription)" }
    }
}
