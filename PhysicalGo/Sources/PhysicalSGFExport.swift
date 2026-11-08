import Foundation

/// Transport adapter for the existing authenticated OGS client; independent of camera and UI.
enum PhysicalSGFExport {
    struct Download { let data: Data; let filename: String }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private struct State: Decodable {
        let token: String
        let game: Int
        let time: Double
        let sgfExport: Bool?
    }
    static let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        .appendingPathComponent("Physical Go/Online Bridge")

    static func download(directory: URL = directory, timeout: Double = 30) async throws -> Download {
        guard let data=try? Data(contentsOf:directory.appendingPathComponent("state.json")),
              let state=try? JSONDecoder().decode(State.self,from:data),state.game>0,
              abs(Date().timeIntervalSince1970-state.time)<3 else {
            throw Failure(message:"Open your game in SGF Player and enable Use physical board.")
        }
        guard state.sgfExport == true else {
            throw Failure(message:"This SGF Player version needs the physical-board export update.")
        }
        let request=PhysicalSGFExportRequest(id:UUID(),token:state.token,game:state.game,time:Date().timeIntervalSince1970)
        let requestURL=directory.appendingPathComponent("sgf-request.json")
        let replyURL=directory.appendingPathComponent("sgf-result.json")
        try JSONEncoder().encode(request).write(to:requestURL,options:.atomic)
        defer {
            // Never remove another export's request or reply.
            if let data=try? Data(contentsOf:requestURL),
               let pending=try? JSONDecoder().decode(PhysicalSGFExportRequest.self,from:data),pending.id==request.id {
                try? FileManager.default.removeItem(at:requestURL)
            }
            if let data=try? Data(contentsOf:replyURL),
               let reply=try? JSONDecoder().decode(PhysicalSGFExportReply.self,from:data),reply.id==request.id {
                try? FileManager.default.removeItem(at:replyURL)
            }
        }
        let start=ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime-start < timeout {
            try Task.checkCancellation()
            if let data=try? Data(contentsOf:replyURL),
               let reply=try? JSONDecoder().decode(PhysicalSGFExportReply.self,from:data),
               reply.id==request.id,reply.game==request.game {
                if let error=reply.error {throw Failure(message:error)}
                guard let sgf=reply.data,let text=String(data:sgf,encoding:.utf8),
                      text.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("(;") else {
                    throw Failure(message:"OGS did not return a valid SGF file.")
                }
                let name=reply.filename.map { URL(fileURLWithPath:$0).lastPathComponent }
                return Download(data:sgf,filename:name?.lowercased().hasSuffix(".sgf") == true ? name! : "OGS game \(request.game).sgf")
            }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        throw Failure(message:"SGF Player did not respond. Keep the game open with Use physical board enabled and try again.")
    }
}
