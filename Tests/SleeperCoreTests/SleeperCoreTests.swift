import Testing
@testable import SleeperCore

@Suite struct MapTests {
    let map = GameMap.abyss

    @Test func everyStationIsWalkableAndReachable() {
        let pf = Pathfinder(map: map)
        for s in map.stations {
            #expect(map.isWalkable(s.pos), "\(s.name) stands on a blocked tile")
            #expect(pf.path(from: map.spawns[0], to: s.pos) != nil, "\(s.name) can't be reached")
        }
    }

    @Test func everySpawnIsWalkable() {
        for s in map.spawns { #expect(map.isWalkable(s)) }
    }

    @Test func roomsAreSurroundedByWalls() {
        // No floor tile touches open water directly.
        for y in 0..<map.height { for x in 0..<map.width where map[TilePos(x, y)] == .floor {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { #expect(map[TilePos(x + dx, y + dy)] != .void) }
        } }
    }

    @Test func wallsBlockSight() {
        // Sonar and Kelp Farm are separated by a wall except for the corridor.
        #expect(!Sight.clear(map, from: TilePos(5, 8).center, to: TilePos(22, 8).center))
        #expect(Sight.clear(map, from: TilePos(20, 15).center, to: TilePos(31, 21).center))
    }
}

@Suite struct GameTests {
    /// Runs a game with the human idle (skipping every vote) until it ends.
    func run(seed: UInt64, role: RoleChoice, limit: Double = 1500) -> Game {
        let g = Game(seed: seed, look: PlayerLook(color: .coral, hat: .captain), roleChoice: role)
        var t = 0.0
        while t < limit {
            if case .over = g.phase { break }
            if case .meeting = g.phase { g.humanVote(.skip) }
            g.step(dt: 1.0 / 30)
            t += 1.0 / 30
        }
        return g
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
    func aiGamesFinish(seed: UInt64) {
        let g = run(seed: seed, role: .crew)
        guard case .over(let w, let reason) = g.phase else {
            Issue.record("Game \(seed) didn't finish: progress \(g.taskProgress)")
            return
        }
        #expect(!reason.isEmpty)
        _ = w
    }

    @Test func crewSometimesWinsAndTraitorSometimesWins() {
        var crew = 0, traitor = 0
        for seed in UInt64(10)..<UInt64(30) {
            if case .over(let w, _) = run(seed: seed, role: .crew).phase { if w == .crew { crew += 1 } else { traitor += 1 } }
        }
        #expect(crew > 0)
        #expect(traitor > 0)
    }

    @Test func roleChoiceIsRespected() {
        #expect(Game(seed: 1, look: PlayerLook(color: .lime, hat: .none), roleChoice: .traitor).me.isTraitor)
        #expect(!Game(seed: 1, look: PlayerLook(color: .lime, hat: .none), roleChoice: .crew).me.isTraitor)
    }

    @Test func playersHaveDistinctColours() {
        let g = Game(seed: 3, look: PlayerLook(color: .gold, hat: .none))
        #expect(Set(g.players.map(\.color)).count == g.players.count)
    }

    @Test func humanTraitorCanKillOnlyWhenCloseAndReady() {
        let g = Game(seed: 5, look: PlayerLook(color: .gold, hat: .none), roleChoice: .traitor)
        while case .intro = g.phase { g.step(dt: 1.0 / 30) }
        #expect(g.killTarget == nil, "cooldown starts non-zero")
        g.players[0].killCooldown = 0
        let victim = 1
        g.players[victim].pos = g.players[0].pos + Vec2(0.8, 0)
        #expect(g.killTarget?.id == victim)
        g.killNearest()
        #expect(!g.players[victim].alive)
        #expect(g.bodies.count == 1)
        #expect(g.me.killCooldown == Tuning.killCooldown)
    }

    @Test func reportingABodyStartsAMeeting() {
        let g = Game(seed: 6, look: PlayerLook(color: .gold, hat: .none), roleChoice: .crew)
        while case .intro = g.phase { g.step(dt: 1.0 / 30) }
        let traitor = g.traitorID
        let victim = g.players.first { !$0.isTraitor && !$0.isHuman }!.id
        g.kill(victim, by: traitor)
        g.players[0].pos = g.bodies[0].pos + Vec2(0.5, 0)
        #expect(g.reportableBody != nil)
        g.reportBody()
        guard case .meeting(let m) = g.phase else { Issue.record("no meeting"); return }
        #expect(m.caller == 0)
    }

    @Test func tieEjectsNobody() {
        let g = Game(seed: 7, look: PlayerLook(color: .gold, hat: .none), roleChoice: .crew)
        while case .intro = g.phase { g.step(dt: 1.0 / 30) }
        g.startMeeting(caller: 0, reason: .emergency)
        g.pendingLines.removeAll()
        let ids = g.players.map(\.id)
        // Two votes each for players 1 and 2, the rest skip.
        for (i, id) in ids.enumerated() {
            let v: Vote = i < 2 ? .player(1) : (i < 4 ? .player(2) : .skip)
            if id == 0 { g.humanVote(v) } else { g.castVote(id, v) }
        }
        guard case .ejection(let e, _) = g.phase else { Issue.record("no ejection"); return }
        #expect(e.ejected == nil)
    }

    @Test func witnessesAccuseTheKiller() {
        let g = Game(seed: 8, look: PlayerLook(color: .gold, hat: .none), roleChoice: .traitor)
        while case .intro = g.phase { g.step(dt: 1.0 / 30) }
        // Everyone is still around the table, so the kill is seen.
        g.kill(1, by: 0)
        let witnesses = g.brains.values.filter { $0.witnessed?.killer == 0 }
        #expect(!witnesses.isEmpty)
        g.players[2].pos = g.bodies[0].pos
        g.report(1, by: 2)
        // Run the meeting out.
        for _ in 0..<(30 * 80) { g.step(dt: 1.0 / 30); if case .meeting = g.phase {} else { break } }
        guard case .ejection(let e, _) = g.phase else { Issue.record("no ejection"); return }
        #expect(e.ejected == 0, "the crew should vote out a traitor caught in the act")
    }

    @Test func oxygenRunningOutLosesForCrew() {
        let g = Game(seed: 9, look: PlayerLook(color: .gold, hat: .none), roleChoice: .traitor)
        while case .intro = g.phase { g.step(dt: 1.0 / 30) }
        // Freeze the AI far from the consoles by making it a meeting-free, AI-free check.
        g.brains.removeAll()
        g.sabotageCooldown = 0
        g.triggerSabotage(.oxygen)
        for _ in 0..<(30 * 50) { g.step(dt: 1.0 / 30) }
        guard case .over(let w, _) = g.phase else { Issue.record("not over"); return }
        #expect(w == .traitor)
    }
}

@Suite struct MeetingHonestyTests {
    /// Honest crew should never be "caught lying" by another crew member's sighting.
    @Test func honestCrewAreNotContradicted() {
        var falseCatches: [String] = []
        var traitorCatches = 0
        for seed in UInt64(200)..<UInt64(240) {
            let g = Game(seed: seed, look: PlayerLook(color: .coral, hat: .none), roleChoice: .crew)
            var seen = Set<Int>()
            for _ in 0..<(30 * 900) {
                if case .over = g.phase { break }
                if case .meeting(let m) = g.phase {
                    g.humanVote(.skip)
                    for l in m.lines where !seen.contains(l.id) && l.text.contains("You weren't in") {
                        seen.insert(l.id)
                        let target = g.players.first { l.text.hasPrefix("Wait, \($0.name),") }!
                        if target.isTraitor { traitorCatches += 1 } else { falseCatches.append("\(seed): \(l.text)") }
                    }
                }
                g.step(dt: 1.0 / 30)
            }
        }
        #expect(falseCatches.isEmpty, "\(falseCatches)")
        print("traitor caught lying \(traitorCatches) times")
    }
}
