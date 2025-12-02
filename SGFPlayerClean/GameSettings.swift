import Foundation
import SwiftUI

// MARK: - Game Settings for Live Play

/// Rules for the game
enum GameRules: String, CaseIterable, Identifiable, Codable {
    case japanese = "Japanese"
    case chinese = "Chinese"
    case aga = "AGA"
    case korean = "Korean"
    case newZealand = "New Zealand"
    case ing = "Ing"

    var id: String { rawValue }
    var apiValue: String { rawValue.lowercased() }
}

/// Time control systems
enum TimeControlSystem: String, CaseIterable, Identifiable, Codable {
    case fischer = "Fischer"
    case byoyomi = "Byo-Yomi"
    case canadian = "Canadian"
    case simple = "Simple"
    case absolute = "Absolute"
    case none = "None"

    var id: String { rawValue }
    var apiValue: String {
        switch self {
        case .byoyomi: return "byoyomi"
        case .fischer: return "fischer"
        case .canadian: return "canadian"
        case .simple: return "simple"
        case .absolute: return "absolute"
        case .none: return "none"
        }
    }
}

/// Handicap options
enum HandicapOption: String, CaseIterable, Identifiable, Codable {
    case automatic = "Automatic"
    case none = "None"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"

    var id: String { rawValue }
    var apiValue: Int {
        switch self {
        case .automatic: return -1
        case .none: return 0
        case .two: return 2
        case .three: return 3
        case .four: return 4
        case .five: return 5
        case .six: return 6
        case .seven: return 7
        case .eight: return 8
        case .nine: return 9
        }
    }
}

/// Komi options
enum KomiOption: String, CaseIterable, Identifiable, Codable {
    case automatic = "Automatic"
    case custom = "Custom"

    var id: String { rawValue }
}

/// Color preference for matchmaking
enum ColorPreference: String, CaseIterable, Identifiable, Codable {
    case automatic = "Automatic"
    case black = "Black"
    case white = "White"

    var id: String { rawValue }

    /// Value for OGS API ("automatic", "black", "white")
    var apiValue: String { rawValue.lowercased() }
}

/// Main time options (in minutes)
let mainTimeOptions = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90]

/// Time per period options (in seconds) - for Byo-Yomi
let periodTimeOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120]

/// Period count options - for Byo-Yomi
let periodCountOptions = [1, 2, 3, 5, 7, 10]

/// Fischer time increment options (in seconds)
let fischerIncrementOptions = [5, 10, 15, 20, 30, 45, 60]

/// Fischer max time options (in minutes)
let fischerMaxTimeOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120]

/// Rank restriction for above/below
enum RankRestriction: Codable, Equatable {
    case any
    case limit(Int)

    var displayValue: String {
        switch self {
        case .any: return "Any"
        case .limit(let value): return "\(value)"
        }
    }
}

/// Game settings for live play on OGS
struct GameSettings: Codable {
    // Basic settings
    var gameName: String
    var inviteOnly: Bool
    var rules: GameRules

    // Board settings
    var boardSize: Int
    var ranked: Bool

    // Handicap & Komi
    var handicap: HandicapOption
    var komi: KomiOption
    var customKomi: Double

    // Time control - Byo-Yomi/Canadian/Simple
    var timeControlSystem: TimeControlSystem
    var mainTimeMinutes: Int
    var periodTimeSeconds: Int  // Byo-Yomi: time per period
    var periods: Int             // Byo-Yomi: number of periods

    // Time control - Fischer
    var fischerIncrementSeconds: Int  // Time added per move
    var fischerMaxTimeMinutes: Int    // Maximum time that can accumulate

    // Player settings
    var colorPreference: ColorPreference
    var disableAnalysis: Bool

    // Rank restrictions
    var restrictRank: Bool
    var ranksAbove: RankRestriction
    var ranksBelow: RankRestriction

    /// Computed: derive game speed from time settings
    var gameSpeed: String {
        let totalSeconds = mainTimeMinutes * 60
        if totalSeconds < 10 * 60 {
            return "blitz"
        } else if totalSeconds < 20 * 60 {
            return "rapid"
        } else if totalSeconds < 24 * 60 * 60 {
            return "live"
        } else {
            return "correspondence"
        }
    }

    /// Default settings for quick play
    static let `default` = GameSettings(
        gameName: "SGFPlayer3D Game",
        inviteOnly: false,
        rules: .japanese,
        boardSize: 19,
        ranked: true,
        handicap: .automatic,
        komi: .automatic,
        customKomi: 6.5,
        timeControlSystem: .byoyomi,
        mainTimeMinutes: 5,
        periodTimeSeconds: 30,
        periods: 5,
        fischerIncrementSeconds: 30,
        fischerMaxTimeMinutes: 10,
        colorPreference: .automatic,
        disableAnalysis: false,
        restrictRank: false,
        ranksAbove: .any,
        ranksBelow: .any
    )

    // MARK: - UserDefaults Keys
    private static let gameNameKey = "gameSettings.gameName"
    private static let inviteOnlyKey = "gameSettings.inviteOnly"
    private static let rulesKey = "gameSettings.rules"
    private static let boardSizeKey = "gameSettings.boardSize"
    private static let rankedKey = "gameSettings.ranked"
    private static let handicapKey = "gameSettings.handicap"
    private static let komiKey = "gameSettings.komi"
    private static let customKomiKey = "gameSettings.customKomi"
    private static let timeControlSystemKey = "gameSettings.timeControlSystem"
    private static let mainTimeMinutesKey = "gameSettings.mainTimeMinutes"
    private static let periodTimeSecondsKey = "gameSettings.periodTimeSeconds"
    private static let periodsKey = "gameSettings.periods"
    private static let fischerIncrementSecondsKey = "gameSettings.fischerIncrementSeconds"
    private static let fischerMaxTimeMinutesKey = "gameSettings.fischerMaxTimeMinutes"
    private static let colorPreferenceKey = "gameSettings.colorPreference"
    private static let disableAnalysisKey = "gameSettings.disableAnalysis"
    private static let restrictRankKey = "gameSettings.restrictRank"

    /// Load settings from UserDefaults
    static func load() -> GameSettings {
        let gameName = UserDefaults.standard.string(forKey: gameNameKey) ?? "SGFPlayer3D Game"
        let inviteOnly = UserDefaults.standard.bool(forKey: inviteOnlyKey)

        let rulesRaw = UserDefaults.standard.string(forKey: rulesKey) ?? GameRules.japanese.rawValue
        let rules = GameRules(rawValue: rulesRaw) ?? .japanese

        let boardSize = UserDefaults.standard.object(forKey: boardSizeKey) as? Int ?? 19
        let ranked = UserDefaults.standard.object(forKey: rankedKey) as? Bool ?? true

        let handicapRaw = UserDefaults.standard.string(forKey: handicapKey) ?? HandicapOption.automatic.rawValue
        let handicap = HandicapOption(rawValue: handicapRaw) ?? .automatic

        let komiRaw = UserDefaults.standard.string(forKey: komiKey) ?? KomiOption.automatic.rawValue
        let komi = KomiOption(rawValue: komiRaw) ?? .automatic
        let customKomi = UserDefaults.standard.double(forKey: customKomiKey)

        let timeControlRaw = UserDefaults.standard.string(forKey: timeControlSystemKey) ?? TimeControlSystem.byoyomi.rawValue
        let timeControlSystem = TimeControlSystem(rawValue: timeControlRaw) ?? .byoyomi

        let mainTimeMinutes = UserDefaults.standard.object(forKey: mainTimeMinutesKey) as? Int ?? 5
        let periodTimeSeconds = UserDefaults.standard.object(forKey: periodTimeSecondsKey) as? Int ?? 30
        let periods = UserDefaults.standard.object(forKey: periodsKey) as? Int ?? 5
        let fischerIncrementSeconds = UserDefaults.standard.object(forKey: fischerIncrementSecondsKey) as? Int ?? 30
        let fischerMaxTimeMinutes = UserDefaults.standard.object(forKey: fischerMaxTimeMinutesKey) as? Int ?? 10

        let colorPrefRaw = UserDefaults.standard.string(forKey: colorPreferenceKey) ?? ColorPreference.automatic.rawValue
        let colorPreference = ColorPreference(rawValue: colorPrefRaw) ?? .automatic

        let disableAnalysis = UserDefaults.standard.bool(forKey: disableAnalysisKey)
        let restrictRank = UserDefaults.standard.bool(forKey: restrictRankKey)

        return GameSettings(
            gameName: gameName,
            inviteOnly: inviteOnly,
            rules: rules,
            boardSize: boardSize,
            ranked: ranked,
            handicap: handicap,
            komi: komi,
            customKomi: customKomi == 0 ? 6.5 : customKomi,
            timeControlSystem: timeControlSystem,
            mainTimeMinutes: mainTimeMinutes,
            periodTimeSeconds: periodTimeSeconds,
            periods: periods,
            fischerIncrementSeconds: fischerIncrementSeconds,
            fischerMaxTimeMinutes: fischerMaxTimeMinutes,
            colorPreference: colorPreference,
            disableAnalysis: disableAnalysis,
            restrictRank: restrictRank,
            ranksAbove: .any,
            ranksBelow: .any
        )
    }

    /// Save settings to UserDefaults
    func save() {
        UserDefaults.standard.set(gameName, forKey: Self.gameNameKey)
        UserDefaults.standard.set(inviteOnly, forKey: Self.inviteOnlyKey)
        UserDefaults.standard.set(rules.rawValue, forKey: Self.rulesKey)
        UserDefaults.standard.set(boardSize, forKey: Self.boardSizeKey)
        UserDefaults.standard.set(ranked, forKey: Self.rankedKey)
        UserDefaults.standard.set(handicap.rawValue, forKey: Self.handicapKey)
        UserDefaults.standard.set(komi.rawValue, forKey: Self.komiKey)
        UserDefaults.standard.set(customKomi, forKey: Self.customKomiKey)
        UserDefaults.standard.set(timeControlSystem.rawValue, forKey: Self.timeControlSystemKey)
        UserDefaults.standard.set(mainTimeMinutes, forKey: Self.mainTimeMinutesKey)
        UserDefaults.standard.set(periodTimeSeconds, forKey: Self.periodTimeSecondsKey)
        UserDefaults.standard.set(periods, forKey: Self.periodsKey)
        UserDefaults.standard.set(fischerIncrementSeconds, forKey: Self.fischerIncrementSecondsKey)
        UserDefaults.standard.set(fischerMaxTimeMinutes, forKey: Self.fischerMaxTimeMinutesKey)
        UserDefaults.standard.set(colorPreference.rawValue, forKey: Self.colorPreferenceKey)
        UserDefaults.standard.set(disableAnalysis, forKey: Self.disableAnalysisKey)
        UserDefaults.standard.set(restrictRank, forKey: Self.restrictRankKey)
    }
}
