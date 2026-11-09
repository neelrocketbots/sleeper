import Foundation

/// A point or vector in tile units. The map's origin is its top-left corner and y grows downward.
public struct Vec2: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    public var length: Double { (x * x + y * y).squareRoot() }
    public var normalized: Vec2 { let l = length; return l > 1e-9 ? Vec2(x / l, y / l) : .zero }
    public func distance(to o: Vec2) -> Double { (self - o).length }
    public var tile: TilePos { TilePos(Int(x.rounded(.down)), Int(y.rounded(.down))) }
}

/// A tile on the map grid.
public struct TilePos: Equatable, Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    /// The centre of the tile, in tile units.
    public var center: Vec2 { Vec2(Double(x) + 0.5, Double(y) + 0.5) }
}

/// A rectangle of tiles, inclusive of `x0...x1` and `y0...y1`.
public struct TileRect: Equatable, Sendable, Codable {
    public var x0: Int, y0: Int, x1: Int, y1: Int
    public init(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) { self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1 }
    public func contains(_ p: TilePos) -> Bool { p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 }
    public var center: Vec2 { Vec2(Double(x0 + x1 + 1) / 2, Double(y0 + y1 + 1) / 2) }
    public var width: Int { x1 - x0 + 1 }
    public var height: Int { y1 - y0 + 1 }
}

/// A small, fast, seedable random number generator (SplitMix64), so games and tests are reproducible.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    public mutating func chance(_ p: Double) -> Bool { unit() < p }
}
