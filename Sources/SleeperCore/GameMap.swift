import Foundation

public enum Tile: UInt8, Sendable {
    /// Open water outside the station: you can see across it.
    case void
    case floor
    /// A dome's hull: blocks walking and sight.
    case wall
    /// Furniture or machinery on a floor tile: blocks walking, not sight.
    case prop
    /// A tunnel's glass wall: blocks walking, not sight.
    case glass
}

/// The art a room's floor and furniture use.
public enum RoomTheme: String, Sendable, CaseIterable {
    case sonar, kelp, pearl, mess, thermal, ballast, pressure, hatchery, corridor
}

/// A dome: a round room. `center` is in tile units; a tile belongs to the dome when its centre is within `radius`.
public struct Room: Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let theme: RoomTheme
    public let center: Vec2
    public let radius: Double
    /// The bounding box of the dome's floor.
    public var rect: TileRect {
        TileRect(Int((center.x - radius).rounded(.down)), Int((center.y - radius).rounded(.down)),
                 Int((center.x + radius).rounded(.up)) - 1, Int((center.y + radius).rounded(.up)) - 1)
    }
    public func contains(_ p: TilePos) -> Bool { p.center.distance(to: center) <= radius }
    public init(id: Int, name: String, theme: RoomTheme, center: Vec2, radius: Double) {
        self.id = id; self.name = name; self.theme = theme; self.center = center; self.radius = radius
    }
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
    /// Only dome hulls block sight: tunnel glass and open water are see-through.
    public func blocksSight(_ p: TilePos) -> Bool { self[p] == .wall }

    /// What tunnels are called in speech and on screen.
    public static let tunnelName = "Tunnel"

    /// The dome containing a tile, or nil in a tunnel.
    public func room(at p: TilePos) -> Room? { rooms.first { $0.contains(p) } }
    public func roomName(at p: TilePos) -> String { room(at: p)?.name ?? Self.tunnelName }

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
        var inDome = [Bool](repeating: false, count: width * height)
        for r in rooms {
            for y in max(0, r.rect.y0)...min(height - 1, r.rect.y1) { for x in max(0, r.rect.x0)...min(width - 1, r.rect.x1)
                where r.contains(TilePos(x, y)) { t[y * width + x] = .floor; inDome[y * width + x] = true } }
        }
        for c in corridors { set(c, .floor) }
        for p in props { set(p.rect, .prop) }
        // Every water tile touching the station becomes hull (next to a dome) or glass (next to tunnels only).
        var walled = t
        for y in 0..<height {
            for x in 0..<width where t[y * width + x] == .void {
                var touches = false, touchesDome = false
                for dy in -1...1 { for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < width, ny < height {
                        let n = t[ny * width + nx]
                        if n == .floor || n == .prop { touches = true; if inDome[ny * width + nx] { touchesDome = true } }
                    }
                } }
                if touches { walled[y * width + x] = touchesDome ? .wall : .glass }
            }
        }
        tiles = walled
    }
}

extension GameMap {
    /// The Abyss: eight domes on the sea floor, joined by glass tunnels, around a central Mess Hall.
    public static let abyss: GameMap = {
        func dome(_ id: Int, _ name: String, _ theme: RoomTheme, _ x: Int, _ y: Int, _ r: Double) -> Room {
            Room(id: id, name: name, theme: theme, center: Vec2(Double(x) + 0.5, Double(y) + 0.5), radius: r)
        }
        let rooms: [Room] = [
            dome(0, "Sonar", .sonar, 8, 8, 5.5),
            dome(1, "Kelp Farm", .kelp, 27, 7, 6.5),
            dome(2, "Pearl Lab", .pearl, 46, 8, 5.5),
            dome(3, "Mess Hall", .mess, 27, 23, 7.5),
            dome(4, "Thermal Vent", .thermal, 8, 24, 5.5),
            dome(5, "Ballast Tanks", .ballast, 46, 24, 5.5),
            dome(6, "Pressure Lock", .pressure, 11, 39, 5.5),
            dome(7, "Hatchery", .hatchery, 43, 39, 5.5),
        ]
        // Tunnels, two tiles wide, each running a little way into the domes it joins.
        let corridors: [TileRect] = [
            TileRect(12, 7, 22, 8), TileRect(32, 7, 42, 8),      // Sonar–Kelp, Kelp–Pearl
            TileRect(26, 12, 27, 17),                             // Kelp–Mess
            TileRect(7, 12, 8, 20), TileRect(45, 12, 46, 20),    // Sonar–Thermal, Pearl–Ballast
            TileRect(12, 23, 21, 24), TileRect(33, 23, 42, 24),  // Thermal–Mess, Mess–Ballast
            TileRect(9, 28, 10, 35), TileRect(44, 28, 45, 35),   // Thermal–Pressure, Ballast–Hatchery
            TileRect(26, 29, 27, 40), TileRect(15, 39, 39, 40),  // Mess south, and the long tunnel along the bottom
        ]
        let table = TileRect(24, 21, 30, 24)
        let props: [Prop] = [
            // Sonar
            Prop(kind: .sonarDish, rect: TileRect(6, 4, 8, 4)), Prop(kind: .chartTable, rect: TileRect(4, 9, 5, 10)),
            // Kelp Farm
            Prop(kind: .kelpTank, rect: TileRect(23, 3, 24, 4)), Prop(kind: .kelpTank, rect: TileRect(30, 3, 31, 4)),
            Prop(kind: .kelpTank, rect: TileRect(27, 2, 28, 2)),
            // Pearl Lab
            Prop(kind: .pearlBench, rect: TileRect(44, 4, 46, 4)), Prop(kind: .console, rect: TileRect(48, 11, 49, 11)),
            // Mess Hall
            Prop(kind: .table, rect: table), Prop(kind: .filter, rect: TileRect(22, 18, 23, 18)),
            // Thermal Vent
            Prop(kind: .ventGrate, rect: TileRect(5, 21, 6, 22)), Prop(kind: .lightPanel, rect: TileRect(10, 20, 11, 20)),
            Prop(kind: .console, rect: TileRect(4, 26, 5, 26)),
            // Ballast Tanks
            Prop(kind: .ballastTank, rect: TileRect(43, 20, 44, 22)), Prop(kind: .ballastTank, rect: TileRect(48, 20, 49, 22)),
            Prop(kind: .oxygenConsole, rect: TileRect(48, 27, 49, 27)),
            // Pressure Lock
            Prop(kind: .sealPanel, rect: TileRect(12, 35, 13, 35)), Prop(kind: .airlock, rect: TileRect(7, 40, 8, 41)),
            Prop(kind: .oxygenConsole, rect: TileRect(12, 43, 13, 43)),
            // Hatchery
            Prop(kind: .eggBed, rect: TileRect(41, 40, 43, 41)), Prop(kind: .feeder, rect: TileRect(41, 35, 42, 35)),
        ]
        var stations: [Station] = []
        func add(_ kind: StationKind, _ room: Int, _ x: Int, _ y: Int) {
            stations.append(Station(id: stations.count, kind: kind, room: room, pos: TilePos(x, y)))
        }
        add(.task(name: "Calibrate sonar", game: .timing), 0, 7, 5)
        add(.task(name: "Chart the trench", game: .sequence), 0, 6, 10)
        add(.task(name: "Water kelp", game: .hold), 1, 23, 5)
        add(.task(name: "Harvest kelp", game: .sequence), 1, 30, 5)
        add(.task(name: "Polish pearls", game: .hold), 2, 45, 5)
        add(.task(name: "Sort samples", game: .sequence), 2, 48, 10)
        add(.task(name: "Clean filters", game: .hold), 3, 22, 19)
        add(.task(name: "Divert heat", game: .timing), 4, 7, 22)
        add(.task(name: "Bleed pressure", game: .sequence), 4, 6, 26)
        add(.task(name: "Balance tanks", game: .timing), 5, 46, 22)
        add(.task(name: "Check seals", game: .sequence), 6, 12, 36)
        add(.task(name: "Cycle airlock", game: .hold), 6, 9, 41)
        add(.task(name: "Warm eggs", game: .timing), 7, 42, 42)
        add(.task(name: "Feed hatchlings", game: .hold), 7, 41, 36)
        add(.emergency, 3, 27, 20)
        add(.fixLights, 4, 10, 21)
        add(.fixOxygen(part: 0), 6, 12, 42)
        add(.fixOxygen(part: 1), 5, 48, 26)
        let spawns = [TilePos(23, 20), TilePos(31, 20), TilePos(23, 25), TilePos(31, 25),
                      TilePos(25, 26), TilePos(29, 26), TilePos(22, 22), TilePos(32, 23)]
        return GameMap(width: 56, height: 47, rooms: rooms, corridors: corridors, props: props, stations: stations,
                       spawns: spawns, meetingTable: table)
    }()
}
