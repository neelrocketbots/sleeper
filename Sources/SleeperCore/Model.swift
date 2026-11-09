import Foundation

/// The twelve player colours. Names are shown in meetings so colour is never the only way to tell players apart.
public enum PlayerColor: Int, CaseIterable, Sendable, Codable {
    case coral, ocean, lime, gold, tangerine, ink, pearl, violet, cyan, rose, cocoa, moss

    public var name: String {
        switch self {
        case .coral: "Coral"; case .ocean: "Ocean"; case .lime: "Lime"; case .gold: "Gold"
        case .tangerine: "Tangerine"; case .ink: "Ink"; case .pearl: "Pearl"; case .violet: "Violet"
        case .cyan: "Cyan"; case .rose: "Rose"; case .cocoa: "Cocoa"; case .moss: "Moss"
        }
    }

    /// The base body colour, 0xRRGGBB.
    public var hex: UInt32 {
        switch self {
        case .coral: 0xFF7A8A; case .ocean: 0x3D6BFF; case .lime: 0x8ADC4B; case .gold: 0xFFC93D
        case .tangerine: 0xFF8A3D; case .ink: 0x4A4366; case .pearl: 0xE6E9F2; case .violet: 0x9B6BFF
        case .cyan: 0x3DD8E0; case .rose: 0xFF6FCF; case .cocoa: 0xA0693F; case .moss: 0x3E9E5B
        }
    }
}

public enum Hat: Int, CaseIterable, Sendable, Codable {
    case none, captain, beanie, headlamp, seashell, crown
    public var name: String {
        switch self {
        case .none: "No hat"; case .captain: "Captain's cap"; case .beanie: "Beanie"; case .headlamp: "Headlamp"
        case .seashell: "Seashell"; case .crown: "Coral crown"
        }
    }
}

public enum Role: Sendable, Equatable { case crew, traitor }

public enum RoleChoice: Sendable, Equatable, CaseIterable {
    case random, crew, traitor
    public var name: String { switch self { case .random: "Random role"; case .crew: "Always crew"; case .traitor: "Always traitor" } }
}

public struct Player: Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let color: PlayerColor
    public let hat: Hat
    public let isHuman: Bool
    public internal(set) var role: Role
    public internal(set) var alive = true
    public internal(set) var pos: Vec2
    /// -1 facing left, 1 facing right.
    public internal(set) var facing: Double = 1
    public internal(set) var moving = false
    /// Grows while walking; the renderer picks walk frames from it.
    public internal(set) var walkPhase: Double = 0
    /// Station ids. A traitor gets fake tasks to stand at.
    public internal(set) var tasks: [Int] = []
    public internal(set) var done: Set<Int> = []
    public internal(set) var killCooldown: Double = 0
    public internal(set) var emergencyLeft = 1
    /// Set while an AI (or the human) is busy at a station; the renderer shows a working pose.
    public internal(set) var working = false

    public var isTraitor: Bool { role == .traitor }
    public var label: String { "\(name) (\(color.name))" }
}

public struct Body: Sendable, Identifiable {
    public var id: Int { victim }
    public let victim: Int
    public let killer: Int
    public let pos: Vec2
    public let time: Double
    public internal(set) var reported = false
}

public enum Sabotage: Sendable, Equatable {
    case none
    case lights
    /// Seconds left, and which of the two consoles are sealed.
    case oxygen(timeLeft: Double, fixed: [Bool])

    public var isActive: Bool { self != .none }
}

public enum SabotageKind: Sendable { case lights, oxygen }

public enum MeetingReason: Sendable, Equatable {
    case body(victim: Int, room: String)
    case emergency
}

public struct MeetingLine: Sendable, Identifiable {
    public let id: Int
    public let speaker: Int
    public var text: String
    public let time: Double
}

public enum Vote: Sendable, Equatable { case player(Int), skip }

public struct Meeting: Sendable {
    public let caller: Int
    public let reason: MeetingReason
    public internal(set) var lines: [MeetingLine] = []
    public internal(set) var votes: [Int: Vote] = [:]
    public internal(set) var elapsed: Double = 0
    public static let duration: Double = 75
    public var timeLeft: Double { max(0, Meeting.duration - elapsed) }
}

public struct Ejection: Sendable {
    /// Nil when nobody was ejected (tie or skip).
    public let ejected: Int?
    public let wasTraitor: Bool
    public let tally: [Int: Int]
    public let skips: Int
}

public enum Winner: Sendable, Equatable { case crew, traitor }

public enum Phase: Sendable {
    /// The role reveal before play starts.
    case intro(timeLeft: Double)
    case playing
    case meeting(Meeting)
    case ejection(Ejection, timeLeft: Double)
    case over(Winner, reason: String)
}

public enum GameEvent: Sendable, Equatable {
    case kill(killer: Int, victim: Int)
    case meetingCalled(by: Int, reason: MeetingReason)
    case sabotage(SabotageKind)
    case sabotageFixed
    case taskDone(player: Int)
    case youDied
}

public struct PlayerLook: Sendable, Equatable {
    public var color: PlayerColor
    public var hat: Hat
    public var name: String
    public init(color: PlayerColor, hat: Hat, name: String = "You") { self.color = color; self.hat = hat; self.name = name }
}

public enum Tuning {
    public static let speed = 4.2
    public static let radius = 0.3
    public static let crewSight = 6.0
    public static let traitorSight = 7.5
    public static let lightsOutSight = 2.2
    public static let killRange = 1.3
    public static let killCooldown = 25.0
    public static let firstKillCooldown = 15.0
    public static let reportRange = 1.8
    public static let useRange = 1.4
    public static let sabotageCooldown = 35.0
    public static let oxygenTime = 45.0
    public static let tasksPerCrew = 5
    public static let introTime = 3.5
    public static let ejectionTime = 5.0
}
