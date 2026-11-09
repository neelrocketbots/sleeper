import Foundation

/// A* over walkable tiles, 8-way with no corner cutting. Paths are lists of tiles from start (excluded) to goal.
public struct Pathfinder: Sendable {
    public let map: GameMap
    public init(map: GameMap) { self.map = map }

    public func path(from start: TilePos, to goal: TilePos) -> [TilePos]? {
        guard map.isWalkable(goal) else { return nil }
        if start == goal { return [] }
        let w = map.width, h = map.height
        func idx(_ p: TilePos) -> Int { p.y * w + p.x }
        var g = [Double](repeating: .infinity, count: w * h)
        var came = [Int](repeating: -1, count: w * h)
        var closed = [Bool](repeating: false, count: w * h)
        var open = BinaryHeap()
        func heuristic(_ p: TilePos) -> Double {
            let dx = Double(abs(p.x - goal.x)), dy = Double(abs(p.y - goal.y))
            return (dx + dy) + (1.4142 - 2) * min(dx, dy)
        }
        g[idx(start)] = 0
        open.push(idx(start), heuristic(start))
        let steps: [(Int, Int, Double)] = [(1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
                                           (1, 1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (-1, -1, 1.4142)]
        while let current = open.pop() {
            if closed[current] { continue }
            closed[current] = true
            let cp = TilePos(current % w, current / w)
            if cp == goal { break }
            for (dx, dy, cost) in steps {
                let np = TilePos(cp.x + dx, cp.y + dy)
                guard map.isWalkable(np) else { continue }
                if dx != 0 && dy != 0 {
                    // No squeezing past a wall corner.
                    guard map.isWalkable(TilePos(cp.x + dx, cp.y)), map.isWalkable(TilePos(cp.x, cp.y + dy)) else { continue }
                }
                let ni = idx(np)
                let ng = g[current] + cost
                if ng < g[ni] {
                    g[ni] = ng
                    came[ni] = current
                    open.push(ni, ng + heuristic(np))
                }
            }
        }
        guard came[idx(goal)] != -1 else { return nil }
        var out: [TilePos] = []
        var c = idx(goal)
        while c != idx(start) {
            out.append(TilePos(c % w, c / w))
            c = came[c]
        }
        return out.reversed()
    }
}

/// A min-heap of (index, priority).
struct BinaryHeap {
    private var items: [(Int, Double)] = []
    mutating func push(_ i: Int, _ p: Double) {
        items.append((i, p))
        var c = items.count - 1
        while c > 0 {
            let parent = (c - 1) / 2
            if items[parent].1 <= items[c].1 { break }
            items.swapAt(parent, c); c = parent
        }
    }
    mutating func pop() -> Int? {
        guard !items.isEmpty else { return nil }
        let top = items[0].0
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var c = 0
            while true {
                let l = 2 * c + 1, r = l + 1
                var m = c
                if l < items.count && items[l].1 < items[m].1 { m = l }
                if r < items.count && items[r].1 < items[m].1 { m = r }
                if m == c { break }
                items.swapAt(m, c); c = m
            }
        }
        return top
    }
}

/// Line of sight on the tile grid: walls and open water block, props don't.
public enum Sight {
    /// With `ignoringTarget`, the tile at `b` itself never blocks (so walls can be seen, not just what's past them).
    public static func clear(_ map: GameMap, from a: Vec2, to b: Vec2, ignoringTarget: Bool = false) -> Bool {
        let target = b.tile
        let d = b - a
        let dist = d.length
        if dist < 0.01 { return true }
        // Step at a quarter tile: cheap, and close enough for 16 px tiles.
        let steps = Int((dist / 0.25).rounded(.up))
        var last = TilePos(Int.min, Int.min)
        for i in 1..<max(steps, 2) {
            let t = Double(i) / Double(steps)
            let p = (a + d * t).tile
            if p == last { continue }
            last = p
            if ignoringTarget && p == target { return true }
            if map.blocksSight(p) { return false }
        }
        return true
    }

    /// Can someone at `a` with sight radius `radius` see `b`?
    public static func sees(_ map: GameMap, from a: Vec2, to b: Vec2, radius: Double) -> Bool {
        a.distance(to: b) <= radius && clear(map, from: a, to: b)
    }
}
