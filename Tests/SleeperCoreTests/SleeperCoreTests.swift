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

    @Test func domeHullsBlockSightButGlassDoesNot() {
        // From inside Sonar you can't see into Kelp Farm: the hulls are in the way.
        #expect(!Sight.clear(map, from: TilePos(8, 11).center, to: TilePos(27, 10).center))
        // Across the Mess Hall, past the table.
        #expect(Sight.clear(map, from: TilePos(22, 20).center, to: TilePos(32, 26).center))
        // From the Sonar–Kelp tunnel, through its glass, out into the water.
        #expect(map[TilePos(16, 6)] == .glass)
        #expect(Sight.clear(map, from: TilePos(16, 7).center, to: TilePos(16, 3).center))
    }

    @Test func domesAreRoundAndTunnelsAreGlass() {
        let mess = map.rooms[3]
        #expect(map.room(at: TilePos(27, 23))?.name == "Mess Hall")
        #expect(map.room(at: TilePos(mess.rect.x0, mess.rect.y0)) == nil, "the bounding box corner is outside the dome")
        #expect(map.roomName(at: TilePos(16, 7)) == GameMap.tunnelName)
        #expect(map.tiles.contains(.glass))
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

@Suite struct ChatTests {
    func meeting() -> Game {
        let g = Game(seed: 21, look: PlayerLook(color: .coral, hat: .none, name: "Coral"), roleChoice: .crew)
        while case .intro = g.phase { g.step(dt: 1.0 / 30) }
        g.debugCallMeeting(caller: 0)
        g.pendingLines.removeAll()
        return g
    }

    @Test func understandsAccusationsVouchesAndAlibis() {
        let g = meeting()
        let a = g.players[1], b = g.players[2]
        let accuse = g.understand("I think \(a.name) is the traitor", from: 0)
        #expect(accuse.contains { if case .accuse(let t, let w) = $0 { return t == a.id && w >= 18 }; return false })
        let vouch = g.understand("\(b.name) was with me the whole time", from: 0)
        #expect(vouch.contains { if case .vouch(let t) = $0 { return t == b.id }; return false })
        let byColour = g.understand("\(a.color.name.lowercased()) is sus", from: 0)
        #expect(byColour.contains { if case .accuse(let t, _) = $0 { return t == a.id }; return false })
        let alibi = g.understand("I was in Kelp Farm", from: 0)
        #expect(alibi.contains { if case .was(let r) = $0 { return r == ["Kelp Farm"] }; return false })
    }

    @Test func typedMessagesAppearAndTheAccusedReplies() {
        let g = meeting()
        let target = g.players.first { !$0.isHuman && $0.alive }!
        g.humanSay(.free("I think \(target.name) did it"))
        guard case .meeting(let m) = g.phase else { Issue.record("no meeting"); return }
        #expect(m.lines.last?.speaker == 0)
        #expect(g.pendingLines.contains { $0.speaker == target.id })
    }
}
