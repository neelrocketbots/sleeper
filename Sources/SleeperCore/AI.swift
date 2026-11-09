import Foundation

/// What an AI remembers and is doing.
final class Brain {
    struct Sighting { var time: Double; var pos: Vec2; var room: String }

    enum Activity {
        case idle
        /// Walking to a station to use it.
        case toStation(Int)
        case working(station: Int, left: Double)
        case wandering
        case waiting(left: Double)
        case toBody(Int)
        case hunting(Int, until: Double)
        case fleeing
    }

    let id: Int
    var activity: Activity = .idle
    var path: [TilePos] = []
    var pathGoal: TilePos?
    var repathTimer = 0.0
    var perceiveTimer = 0.0
    var stuckTimer = 0.0
    var lastPos = Vec2.zero

    var sightings: [Int: Sighting] = [:]
    var suspicion: [Int: Double] = [:]
    var witnessed: (killer: Int, victim: Int, room: String)?
    var noticedBody: Int?
    /// Decided once per sabotage: the station this AI goes to fix, or -1 for "not me".
    var sabotageResponse: Int?
    var lastRoom = "Mess Hall"
    /// Where this AI has been: (time it entered, room name or "Corridor").
    var roomLog: [(time: Double, room: String)] = []
    var lastTask: String?
    var selfReportAt: Double?
    var lastVictim: Int?
    /// Fake tasks a traitor has already pretended to do this lap.
    var fakeDone: Set<Int> = []

    init(id: Int) { self.id = id }

    func afterMeeting() {
        activity = .idle
        path = []
        pathGoal = nil
        witnessed = nil
        noticedBody = nil
        sabotageResponse = nil
        selfReportAt = nil
        for (k, v) in suspicion { suspicion[k] = v * 0.6 }
    }
}

/// A claim made in a meeting, with how much it should move other players' suspicion.
enum Claim {
    case accuse(Int, weight: Double)
    case vouch(Int)
    /// "I was in these rooms just before the meeting."
    case was([String])
}

extension Brain {
    /// Every room (not corridor) this AI was in during the window, oldest first.
    func rooms(from t0: Double, to t1: Double) -> [String] {
        var out: [String] = []
        for (i, e) in roomLog.enumerated() {
            let end = i + 1 < roomLog.count ? roomLog[i + 1].time : t1
            guard end >= t0, e.time <= t1, e.room != "Corridor" else { continue }
            if out.last != e.room { out.removeAll { $0 == e.room }; out.append(e.room) }
        }
        return out
    }
}

/// The window before a meeting that alibis talk about.
let alibiWindow = 15.0

/// Speech for a room list: the last three, "A, B, then C".
func roomList(_ all: [String]) -> String {
    let rooms = Array(all.suffix(3))
    switch rooms.count {
    case 0: return "the corridors"
    case 1: return rooms[0]
    default: return rooms.dropLast().joined(separator: ", ") + ", then " + rooms.last!
    }
}

extension Game {
    // MARK: Per-tick AI

    func think(_ id: Int, dt: Double) {
        guard let b = brains[id] else { return }
        let p = players[id]
        players[id].working = false

        b.perceiveTimer -= dt
        if b.perceiveTimer <= 0 {
            b.perceiveTimer = 0.25
            perceive(b)
        }
        let here = map.roomName(at: p.pos.tile)
        if here != "Corridor" { b.lastRoom = here }
        if b.roomLog.last?.room != here {
            b.roomLog.append((time, here))
            if b.roomLog.count > 40 { b.roomLog.removeFirst(b.roomLog.count - 40) }
        }

        if p.isTraitor && p.alive { traitorThink(b, dt: dt) } else { crewThink(b, dt: dt) }
        followPath(b, dt: dt)
    }

    private func perceive(_ b: Brain) {
        let me = players[b.id]
        guard me.alive else { return }
        for o in players where o.id != b.id && o.alive && canSee(me, o.pos) {
            b.sightings[o.id] = Brain.Sighting(time: time, pos: o.pos, room: map.roomName(at: o.pos.tile))
        }
        if !me.isTraitor, b.noticedBody == nil,
           let body = bodies.first(where: { !$0.reported && canSee(me, $0.pos) }) {
            b.noticedBody = body.victim
        }
    }

    // MARK: Crew

    private func crewThink(_ b: Brain, dt: Double) {
        let p = players[b.id]
        // 1. A body: go and report it.
        if p.alive, let v = b.noticedBody, let body = bodies.first(where: { $0.victim == v && !$0.reported }) {
            if body.pos.distance(to: p.pos) <= Tuning.reportRange - 0.2 {
                report(v, by: b.id)
                return
            }
            if case .toBody = b.activity {} else { b.activity = .toBody(v) }
            setGoal(b, body.pos.tile)
            return
        }
        // 2. A sabotage: maybe go and fix it.
        if p.alive, sabotage.isActive {
            if b.sabotageResponse == nil { b.sabotageResponse = chooseFix(b) }
            if let sid = b.sabotageResponse, sid >= 0, canStillFix(sid) {
                workAt(b, station: sid, duration: 2.0, dt: dt)
                return
            }
        }
        // 3. Tasks, then wander.
        taskLoop(b, dt: dt, fake: false)
    }

    private func chooseFix(_ b: Brain) -> Int {
        let p = players[b.id]
        let fixes = map.stations.filter {
            switch $0.kind { case .fixLights: return sabotage == .lights; case .fixOxygen: return canStillFix($0.id); default: return false }
        }
        guard let nearest = fixes.min(by: { $0.pos.center.distance(to: p.pos) < $1.pos.center.distance(to: p.pos) }) else { return -1 }
        return rng.chance(sabotage == .lights ? 0.45 : 0.7) ? nearest.id : -1
    }

    private func canStillFix(_ sid: Int) -> Bool {
        switch map.station(sid).kind {
        case .fixLights: return sabotage == .lights
        case .fixOxygen(let part):
            if case .oxygen(_, let fixed) = sabotage { return !fixed[part] }
            return false
        default: return false
        }
    }

    /// Walk to a station, stand there for `duration`, then use it.
    private func workAt(_ b: Brain, station sid: Int, duration: Double, dt: Double) {
        let s = map.station(sid)
        let p = players[b.id]
        switch b.activity {
        case .working(let wsid, let left) where wsid == sid:
            players[b.id].working = true
            if left - dt <= 0 {
                b.activity = .idle
                complete(station: sid, by: b.id)
            } else {
                b.activity = .working(station: sid, left: left - dt)
            }
        default:
            if s.pos.center.distance(to: p.pos) < 0.35 {
                b.path = []
                b.activity = .working(station: sid, left: duration)
            } else {
                b.activity = .toStation(sid)
                setGoal(b, s.pos)
            }
        }
    }

    private func taskLoop(_ b: Brain, dt: Double, fake: Bool) {
        let p = players[b.id]
        switch b.activity {
        case .working(let sid, let left):
            players[b.id].working = true
            if left - dt <= 0 {
                let s = map.station(sid)
                b.lastTask = s.name
                if !fake, s.isTask { complete(station: sid, by: b.id) }
                if fake { b.fakeDone.insert(sid) }
                b.activity = .idle
            } else {
                b.activity = .working(station: sid, left: left - dt)
            }
            return
        case .toStation(let sid):
            let s = map.station(sid)
            if s.pos.center.distance(to: p.pos) < 0.35 {
                b.path = []
                b.activity = .working(station: sid, left: 2.5 + rng.unit() * 3)
            } else {
                setGoal(b, s.pos)
            }
            return
        case .waiting(let left):
            b.activity = left - dt <= 0 ? .idle : .waiting(left: left - dt)
            return
        case .wandering:
            if b.path.isEmpty { b.activity = .waiting(left: 1 + rng.unit() * 3) }
            return
        default:
            break
        }
        // Idle: pick the nearest unfinished task.
        let remaining = p.tasks.filter { fake ? !b.fakeDone.contains($0) : !p.done.contains($0) }
        if let next = remaining.min(by: {
            map.station($0).pos.center.distance(to: p.pos) < map.station($1).pos.center.distance(to: p.pos)
        }) {
            b.activity = .toStation(next)
            setGoal(b, map.station(next).pos)
        } else {
            if fake { b.fakeDone.removeAll() }
            let r = map.rooms[Int.random(in: 0..<map.rooms.count, using: &rng)]
            if let t = randomFloor(in: r.rect) {
                b.activity = .wandering
                setGoal(b, t)
            }
        }
    }

    private func randomFloor(in r: TileRect) -> TilePos? {
        for _ in 0..<20 {
            let t = TilePos(Int.random(in: r.x0...r.x1, using: &rng), Int.random(in: r.y0...r.y1, using: &rng))
            if map.isWalkable(t) { return t }
        }
        return nil
    }

    // MARK: Traitor

    private func traitorThink(_ b: Brain, dt: Double) {
        let p = players[b.id]
        // Self-report after a kill, sometimes.
        if let at = b.selfReportAt, time >= at, let v = b.lastVictim,
           let body = bodies.first(where: { $0.victim == v && !$0.reported }) {
            if body.pos.distance(to: p.pos) <= Tuning.reportRange - 0.2 { b.selfReportAt = nil; report(v, by: b.id); return }
            setGoal(b, body.pos.tile)
            return
        }
        // Kill when nobody else can see.
        if p.killCooldown <= 0 {
            let targets = players.filter { $0.alive && !$0.isTraitor && $0.pos.distance(to: p.pos) <= Tuning.killRange }
            if let t = targets.first, !hasWitness(killer: p, victim: t) {
                kill(t.id, by: b.id)
                b.lastVictim = t.id
                b.selfReportAt = rng.chance(0.2) ? time + 2.5 : nil
                b.activity = .fleeing
                let far = map.taskStations.max { $0.pos.center.distance(to: p.pos) < $1.pos.center.distance(to: p.pos) }!
                setGoal(b, far.pos)
                return
            }
        }
        if case .fleeing = b.activity {
            if b.path.isEmpty { b.activity = .idle } else { return }
        }
        // Sabotage now and then.
        if sabotage == .none, sabotageCooldown <= 0, time > 25, rng.chance(dt * 0.035) {
            startSabotage(rng.chance(0.6) ? .lights : .oxygen)
        }
        // Hunt someone who is alone.
        if p.killCooldown <= 0 {
            if case .hunting(let tid, let until) = b.activity {
                if time > until || !players[tid].alive { b.activity = .idle } else {
                    b.repathTimer -= dt
                    if b.repathTimer <= 0 { b.repathTimer = 0.4; b.pathGoal = nil; setGoal(b, players[tid].pos.tile) }
                    return
                }
            } else if let prey = players.first(where: { $0.alive && !$0.isTraitor && canSee(p, $0.pos) && isAlone($0) }) {
                b.activity = .hunting(prey.id, until: time + 9)
                setGoal(b, prey.pos.tile)
                return
            }
        }
        taskLoop(b, dt: dt, fake: true)
    }

    /// Is anyone other than the killer and the victim able to see either of them?
    func hasWitness(killer: Player, victim: Player) -> Bool {
        players.contains { o in
            o.alive && o.id != killer.id && o.id != victim.id && !o.isTraitor
                && (canSee(o, killer.pos) || canSee(o, victim.pos))
        }
    }

    private func isAlone(_ t: Player) -> Bool {
        !players.contains { $0.alive && $0.id != t.id && !$0.isTraitor && canSee($0, t.pos) }
    }

    // MARK: Movement

    func setGoal(_ b: Brain, _ goal: TilePos) {
        if b.pathGoal == goal && !b.path.isEmpty { return }
        let start = players[b.id].pos.tile
        b.pathGoal = goal
        b.path = pathfinder.path(from: start, to: goal) ?? []
        b.stuckTimer = 0
    }

    private func followPath(_ b: Brain, dt: Double) {
        guard !b.path.isEmpty else { move(b.id, by: .zero, dt: dt); return }
        let p = players[b.id]
        let target = b.path[0].center
        let d = target - p.pos
        let step = Tuning.speed * dt
        if d.length <= step {
            move(b.id, by: d, dt: dt)
            b.path.removeFirst()
        } else {
            move(b.id, by: d.normalized * step, dt: dt)
        }
        // Unstick: if barely moving for a second, re-plan from where we are.
        if players[b.id].pos.distance(to: b.lastPos) < 0.01 { b.stuckTimer += dt } else { b.stuckTimer = 0 }
        b.lastPos = players[b.id].pos
        if b.stuckTimer > 1, let g = b.pathGoal {
            b.pathGoal = nil
            b.path = []
            // Nudge to the tile centre, then try again.
            players[b.id].pos = players[b.id].pos.tile.center
            setGoal(b, g)
        }
    }

    // MARK: Meetings

    func planMeeting(caller: Int, reason: MeetingReason) {
        pendingLines.removeAll()
        let body: Body? = {
            if case .body(let v, _) = reason { return bodies.first { $0.victim == v } }
            return nil
        }()
        // Suspicion from what each AI saw around the body.
        if let body {
            for (id, b) in brains where players[id].alive && !players[id].isTraitor {
                for (o, s) in b.sightings where o != id && players[o].alive {
                    if abs(s.time - body.time) < 12 && s.pos.distance(to: body.pos) < 5.5 { b.suspicion[o, default: 0] += 35 }
                }
                if let w = b.witnessed { b.suspicion[w.killer, default: 0] += 200 }
            }
        }
        var speakers = players.filter { $0.alive && !$0.isHuman }.map(\.id).filter { $0 != caller }
        speakers.shuffle(using: &rng)
        if !players[caller].isHuman { speakers.insert(caller, at: 0) }
        var t = 2.0
        for id in speakers {
            for (text, claims) in compose(id, caller: caller, reason: reason, body: body) {
                // Accusations keep their exact wording; the on-device model only restyles alibis and reports.
                let safe = !claims.contains { if case .accuse = $0 { return true }; return false }
                pendingLines.append(PendingLine(at: t, speaker: id, action: .say(text, effect: nil), claims: claims, rephrase: safe))
                t += 2.2 + rng.unit() * 1.6
            }
        }
        // Votes come after the talking, spread out.
        for id in players.filter({ $0.alive && !$0.isHuman }).map(\.id) {
            pendingLines.append(PendingLine(at: t + 4 + rng.unit() * 14, speaker: id, action: .vote, claims: []))
        }
    }

    /// What an AI says: one or two lines, each with the claims it makes.
    private func compose(_ id: Int, caller: Int, reason: MeetingReason, body: Body?) -> [(String, [Claim])] {
        guard let b = brains[id] else { return [] }
        let me = players[id]
        var out: [(String, [Claim])] = []
        let name = { (i: Int) in self.players[i].name }

        if me.isTraitor {
            if id == caller, let body {
                out.append(("I found \(name(body.victim)) in \(map.roomName(at: body.pos.tile)). I'd only just walked in.", []))
            } else if id == caller {
                out.append(("I called this. Something feels off. Where was everyone?", []))
            }
            // An alibi: true if it's safe, a lie if it would put me at the scene.
            let bodyRoom = body.map { map.roomName(at: $0.pos.tile) }
            // Tell the truth, minus the room with the body. Only invent a room when there's nothing else to say.
            var claim = b.rooms(from: meetingStart - alibiWindow, to: meetingStart).filter { $0 != bodyRoom }
            if claim.isEmpty {
                let others = map.rooms.map(\.name).filter { $0 != bodyRoom }
                claim = [others[Int.random(in: 0..<others.count, using: &rng)]]
            }
            let task = map.taskStations.first { map.rooms[$0.room].name == claim.last }?.name.lowercased() ?? "checking pipes"
            out.append(("I was in \(roomList(claim)), \(task).", [.was(claim)]))
            // Point at someone, to muddy things.
            if rng.chance(0.5) {
                let pool = players.filter { $0.alive && $0.id != id }.map(\.id)
                if let scapegoat = pool.max(by: { (b.sightings[$0]?.time ?? 0) < (b.sightings[$1]?.time ?? 0) }) {
                    let where_ = bodyRoom ?? b.sightings[scapegoat]?.room ?? "the corridor"
                    out.append(("\(name(scapegoat)) was heading toward \(where_) earlier.", [.accuse(scapegoat, weight: 14)]))
                }
            }
            return out
        }

        if let w = b.witnessed {
            out.append(("\(name(w.killer)) took out \(name(w.victim)) in \(w.room)! I saw it happen.", [.accuse(w.killer, weight: 70)]))
            return out
        }
        if id == caller, let body {
            out.append(("I found \(name(body.victim)) in \(map.roomName(at: body.pos.tile)).", []))
        } else if id == caller {
            out.append(("I called this to check in. Where was everyone?", []))
        }
        let rooms = b.rooms(from: meetingStart - alibiWindow, to: meetingStart)
        var alibi = "I was in \(roomList(rooms))"
        if let task = b.lastTask, rooms.count < 2 { alibi += ", \(task.lowercased())" }
        var claims: [Claim] = [.was(rooms)]
        // Vouch for someone seen in the same room just now.
        if let buddy = b.sightings.filter({ rooms.contains($0.value.room) && time - $0.value.time < 10 && players[$0.key].alive && $0.key != id })
            .map(\.key).sorted().first {
            alibi += ". \(name(buddy)) was there too"
            claims.append(.vouch(buddy))
        }
        out.append((alibi + ".", claims))
        if let top = b.suspicion.filter({ players[$0.key].alive && $0.key != id }).max(by: { $0.value < $1.value }), top.value >= 35 {
            let s = b.sightings[top.key]
            let line = s.map { "I saw \(name(top.key)) near \($0.room) right before. That's suspicious." }
                ?? "I don't trust \(name(top.key))."
            out.append((line, [.accuse(top.key, weight: 25)]))
        }
        return out
    }

    /// Everyone (except the speaker) hears a claim and updates who they suspect.
    func hear(_ claims: [Claim], from speaker: Int) {
        for (id, b) in brains where id != speaker && players[id].alive {
            let trust = 1 - min((b.suspicion[speaker] ?? 0) / 100, 0.85)
            for c in claims {
                switch c {
                case .accuse(let t, let w):
                    if t == id {
                        // Wrongly accused (as crew): the accuser looks worse.
                        if !players[id].isTraitor { b.suspicion[speaker, default: 0] += 20 }
                    } else {
                        b.suspicion[t, default: 0] += w * trust
                    }
                case .vouch(let t):
                    if t != id { b.suspicion[t, default: 0] -= 10 * trust }
                case .was(let rooms):
                    // Caught out: I saw them somewhere else in the same stretch of time.
                    guard !players[id].isTraitor, !rooms.isEmpty, let s = b.sightings[speaker], !rooms.contains(s.room),
                          s.room != "Corridor", s.time >= meetingStart - alibiWindow, s.time <= meetingStart else { continue }
                    b.suspicion[speaker, default: 0] += 40
                    let reply = "Wait, \(players[speaker].name), I saw you in \(s.room) just before. You weren't in \(roomList(rooms))."
                    if case .meeting(let m) = phase {
                        pendingLines.append(PendingLine(at: m.elapsed + 1.5 + rng.unit(), speaker: id,
                                                        action: .say(reply, effect: nil), claims: [.accuse(speaker, weight: 30)], rephrase: false))
                    }
                }
            }
        }
    }

    func hear(_ s: HumanStatement, from speaker: Int) {
        switch s {
        case .accuse(let t): hear([.accuse(t, weight: 18)], from: speaker)
        case .vouch(let t): hear([.vouch(t)], from: speaker)
        case .was(let room): hear([.was([room])], from: speaker)
        case .saw(let t, _): hear([.accuse(t, weight: 8)], from: speaker)
        }
    }

    func aiVote(_ id: Int) -> Vote {
        guard let b = brains[id] else { return .skip }
        let candidates = players.filter { $0.alive && $0.id != id }
        if players[id].isTraitor {
            // Go with the crowd: whoever the crew suspects most.
            var crowd: [Int: Double] = [:]
            for (cid, cb) in brains where cid != id && players[cid].alive {
                for (t, v) in cb.suspicion where t != id { crowd[t, default: 0] += v }
            }
            if let top = crowd.filter({ players[$0.key].alive && $0.key != id }).max(by: { $0.value < $1.value }), top.value >= 40 {
                return .player(top.key)
            }
            return .skip
        }
        if let w = b.witnessed, players[w.killer].alive { return .player(w.killer) }
        guard let top = candidates.map({ ($0.id, b.suspicion[$0.id] ?? 0) }).max(by: { $0.1 < $1.1 }), top.1 >= 30 else {
            return .skip
        }
        return .player(top.0)
    }
}
