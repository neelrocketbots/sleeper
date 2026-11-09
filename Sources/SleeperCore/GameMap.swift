import Foundation

public enum Tile: UInt8, Sendable {
    /// Open water outside the station.
    case void
    case floor
    case wall
    /// Furniture or machinery on a floor tile: blocks walking, not sight.
    case prop
}

/// The art a room's floor and furniture use.
public enum RoomTheme: String, Sendable, CaseIterable {
    case sonar, kelp, pearl, mess, thermal, ballast, pressure, hatchery, corridor
}

public struct Room: Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let theme: RoomTheme
    public let rect: TileRect
}

/// The three mini-games a task can use.
public enum MiniGame: String, Sendable, CaseIterable {
    /// Hold the action key until a gauge fills.
    case hold
    /// Press a short sequence of arrow keys.
    case sequence
    /// Stop a moving needle inside a target zone, three times.
    case timing
}

public enum PropKind: String, Sendable, CaseIterable {
    case console, kelpTank, pearlBench, table, filter, ventGrate, lightPanel, ballastTank, sealPanel, oxygenConsole,
         airlock, eggBed, feeder, sonarDish, chartTable
}

/// Furniture or a machine occupying a rectangle of floor tiles.
public struct Prop: Sendable {
    public let kind: PropKind
    public let rect: TileRect
}

public enum StationKind: Equatable, Sendable {
    case task(name: String, game: MiniGame)
    case emergency
    case fixLights
    case fixOxygen(part: Int)
}

/// A place a player can use. `pos` is the floor tile you stand on; the machine is next to it.
public struct Station: Sendable, Identifiable {
    public let id: Int
    public let kind: StationKind
    public let room: Int
    public let pos: TilePos
    public var name: String {
        switch kind {
        case .task(let n, _): return n
        case .emergency: return "Emergency meeting"
        case .fixLights: return "Restore lights"
        case .fixOxygen: return "Seal oxygen leak"
        }
    }
    public var isTask: Bool { if case .task = kind { return true } else { return false } }
}

public struct GameMap: Sendable {
    public let width: Int
    public let height: Int
    public private(set) var tiles: [Tile]
    public let rooms: [Room]
    public let corridors: [TileRect]
    public let props: [Prop]
    public let stations: [Station]
    public let spawns: [TilePos]
    /// The Mess Hall table: the emergency button is used from anywhere next to it, and meetings gather around it.
    public let meetingTable: TileRect

    public subscript(_ p: TilePos) -> Tile {
        guard p.x >= 0, p.y >= 0, p.x < width, p.y < height else { return .void }
        return tiles[p.y * width + p.x]
    }

    public func isWalkable(_ p: TilePos) -> Bool { self[p] == .floor }
    /// Walls and open water block sight; props do not.
    public func blocksSight(_ p: TilePos) -> Bool { let t = self[p]; return t == .wall || t == .void }

    /// The room containing a tile, or nil in a corridor.
    public func room(at p: TilePos) -> Room? { rooms.first { $0.rect.contains(p) } }
    public func roomName(at p: TilePos) -> String { room(at: p)?.name ?? "Corridor" }

    public var taskStations: [Station] { stations.filter(\.isTask) }
    public func station(_ id: Int) -> Station { stations[id] }

    /// The station of a kind, for sabotage fixes.
    public func stations(where match: (StationKind) -> Bool) -> [Station] { stations.filter { match($0.kind) } }

    init(width: Int, height: Int, rooms: [Room], corridors: [TileRect], props: [Prop], stations: [Station],
         spawns: [TilePos], meetingTable: TileRect) {
        self.width = width; self.height = height
        self.rooms = rooms; self.corridors = corridors; self.props = props; self.stations = stations
        self.spawns = spawns; self.meetingTable = meetingTable
        var t = [Tile](repeating: .void, count: width * height)
        func set(_ r: TileRect, _ v: Tile) {
            for y in r.y0...r.y1 { for x in r.x0...r.x1 where x >= 0 && y >= 0 && x < width && y < height { t[y * width + x] = v } }
        }
        for r in rooms { set(r.rect, .floor) }
        for c in corridors { set(c, .floor) }
        for p in props { set(p.rect, .prop) }
        // Every non-floor tile touching a floor or prop tile becomes wall.
        var walled = t
        for y in 0..<height {
            for x in 0..<width where t[y * width + x] == .void {
                var touches = false
                for dy in -1...1 { for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < width, ny < height {
                        let n = t[ny * width + nx]
                        if n == .floor || n == .prop { touches = true }
                    }
                } }
                if touches { walled[y * width + x] = .wall }
            }
        }
        tiles = walled
    }
}

extension GameMap {
    /// The Abyss: eight rooms on the sea floor around a central Mess Hall.
    public static let abyss: GameMap = {
        let rooms: [Room] = [
            Room(id: 0, name: "Sonar", theme: .sonar, rect: TileRect(2, 2, 13, 9)),
            Room(id: 1, name: "Kelp Farm", theme: .kelp, rect: TileRect(19, 2, 32, 9)),
            Room(id: 2, name: "Pearl Lab", theme: .pearl, rect: TileRect(38, 2, 49, 10)),
            Room(id: 3, name: "Mess Hall", theme: .mess, rect: TileRect(17, 13, 34, 22)),
            Room(id: 4, name: "Thermal Vent", theme: .thermal, rect: TileRect(2, 14, 12, 23)),
            Room(id: 5, name: "Ballast Tanks", theme: .ballast, rect: TileRect(39, 14, 49, 23)),
            Room(id: 6, name: "Pressure Lock", theme: .pressure, rect: TileRect(4, 27, 17, 33)),
            Room(id: 7, name: "Hatchery", theme: .hatchery, rect: TileRect(34, 27, 47, 33)),
        ]
        let corridors: [TileRect] = [
            TileRect(14, 5, 18, 6), TileRect(33, 5, 37, 6), TileRect(25, 10, 26, 12), TileRect(7, 10, 8, 13),
            TileRect(43, 11, 44, 13), TileRect(13, 17, 16, 18), TileRect(35, 17, 38, 18), TileRect(25, 23, 26, 28),
            TileRect(18, 29, 33, 30), TileRect(7, 24, 8, 26), TileRect(43, 24, 44, 26),
        ]
        let table = TileRect(23, 16, 28, 19)
        let props: [Prop] = [
            // Sonar
            Prop(kind: .sonarDish, rect: TileRect(4, 2, 6, 2)), Prop(kind: .console, rect: TileRect(10, 2, 12, 2)),
            Prop(kind: .chartTable, rect: TileRect(5, 6, 7, 7)),
            // Kelp Farm
            Prop(kind: .kelpTank, rect: TileRect(21, 4, 22, 5)), Prop(kind: .kelpTank, rect: TileRect(28, 4, 29, 5)),
            Prop(kind: .kelpTank, rect: TileRect(24, 3, 24, 4)),
            // Pearl Lab
            Prop(kind: .pearlBench, rect: TileRect(40, 2, 42, 2)), Prop(kind: .console, rect: TileRect(47, 2, 48, 2)),
            Prop(kind: .pearlBench, rect: TileRect(42, 7, 44, 8)),
            // Mess Hall
            Prop(kind: .table, rect: table), Prop(kind: .filter, rect: TileRect(17, 13, 18, 13)),
            // Thermal Vent
            Prop(kind: .ventGrate, rect: TileRect(4, 15, 5, 16)), Prop(kind: .lightPanel, rect: TileRect(10, 14, 11, 14)),
            Prop(kind: .console, rect: TileRect(2, 23, 3, 23)),
            // Ballast Tanks
            Prop(kind: .ballastTank, rect: TileRect(41, 15, 42, 17)), Prop(kind: .ballastTank, rect: TileRect(46, 15, 47, 17)),
            Prop(kind: .oxygenConsole, rect: TileRect(48, 23, 49, 23)),
            // Pressure Lock
            Prop(kind: .sealPanel, rect: TileRect(5, 27, 6, 27)), Prop(kind: .airlock, rect: TileRect(10, 33, 11, 33)),
            Prop(kind: .oxygenConsole, rect: TileRect(16, 33, 17, 33)),
            // Hatchery
            Prop(kind: .eggBed, rect: TileRect(36, 29, 38, 30)), Prop(kind: .feeder, rect: TileRect(45, 27, 46, 27)),
        ]
        var stations: [Station] = []
        func add(_ kind: StationKind, _ room: Int, _ x: Int, _ y: Int) {
            stations.append(Station(id: stations.count, kind: kind, room: room, pos: TilePos(x, y)))
        }
        add(.task(name: "Calibrate sonar", game: .timing), 0, 5, 3)
        add(.task(name: "Chart the trench", game: .sequence), 0, 11, 3)
        add(.task(name: "Water kelp", game: .hold), 1, 21, 6)
        add(.task(name: "Harvest kelp", game: .sequence), 1, 28, 6)
        add(.task(name: "Polish pearls", game: .hold), 2, 41, 3)
        add(.task(name: "Sort samples", game: .sequence), 2, 47, 3)
        add(.task(name: "Clean filters", game: .hold), 3, 18, 14)
        add(.task(name: "Divert heat", game: .timing), 4, 6, 16)
        add(.task(name: "Bleed pressure", game: .sequence), 4, 3, 22)
        add(.task(name: "Balance tanks", game: .timing), 5, 44, 16)
        add(.task(name: "Check seals", game: .sequence), 6, 5, 28)
        add(.task(name: "Cycle airlock", game: .hold), 6, 10, 32)
        add(.task(name: "Warm eggs", game: .timing), 7, 37, 31)
        add(.task(name: "Feed hatchlings", game: .hold), 7, 45, 28)
        add(.emergency, 3, 25, 15)
        add(.fixLights, 4, 10, 15)
        add(.fixOxygen(part: 0), 6, 16, 32)
        add(.fixOxygen(part: 1), 5, 48, 22)
        let spawns = [TilePos(21, 15), TilePos(30, 15), TilePos(21, 20), TilePos(30, 20),
                      TilePos(23, 21), TilePos(28, 21), TilePos(20, 17), TilePos(31, 18)]
        return GameMap(width: 52, height: 36, rooms: rooms, corridors: corridors, props: props, stations: stations,
                       spawns: spawns, meetingTable: table)
    }()
}
