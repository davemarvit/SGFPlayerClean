import Combine
import Foundation

// The shared replay engine only needs this publisher. The saver deliberately
// does not link the application's preference, audio, AI or networking services.
final class AppSettings {
    static let shared = AppSettings()
    @Published var moveInterval: TimeInterval = 1.5
}
