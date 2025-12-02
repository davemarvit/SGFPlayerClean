import Foundation

class TimeControlManager: ObservableObject {
    @Published var blackTime: String = "00:00"
    @Published var whiteTime: String = "00:00"
    
    init() {}
}
