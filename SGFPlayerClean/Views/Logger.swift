//
//  Logger.swift
//  SGFPlayerClean
//
//  v3.155: Console Mode.
//  - Redirects all logs to Xcode Console via NSLog.
//  - Removes UI storage to prevent memory overhead/scrolling issues.
//

import Foundation

class Logger: ObservableObject {
    static let shared = Logger()
    
    // Kept for compatibility, but empty so UI doesn't render it
    @Published var logs: [LogEntry] = []
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let time = Date()
        let text: String
        let type: LogType
    }
    
    enum LogType {
        case info, success, error, network
    }
    
    func log(_ text: String, type: LogType = .info) {
        // Use NSLog for guaranteed visibility in Xcode Console
        let prefix: String
        switch type {
        case .info: prefix = "ℹ️ [INFO]"
        case .success: prefix = "✅ [SUCCESS]"
        case .error: prefix = "🚨 [ERROR]"
        case .network: prefix = "🌍 [NET]"
        }
        
        NSLog("\(prefix) \(text)")
    }
    
    func clear() {
        // No-op
    }
}
