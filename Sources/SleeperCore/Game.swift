import Foundation

/// One round of Sleeper. Drive it with `step(dt:)` at a fixed rate; the human player is `players[you]`.
/// Not thread-safe: use it from one actor (the app uses the main actor).
public final class Game {
    public let map: GameMap
    public let pathfinder: Pathfinder
    public internal(set) var players: [Player]
    public internal(set) var bodies: [Body] = []
    public internal(set) var phase: Phase
    public internal(set) var time: Double = 0
    public internal(set) var sabotage: Sabotage = .none
    public internal(set) var sabotageCooldown: Double = 20
    public internal(set) var lastEjection: Ejection?
    public let you = 0
    /// The human's movement input, each axis -1...1. Set it every frame.
    public var input: Vec2 = .zero
    /// Events since the UI last drained them.
    public internal(set) var events: [GameEvent] = []

    var rng: SeededRandom
    var brains: [Int: Brain] = [:]
    private var nextLineID = 0
    /// AI lines waiting to be said in the current meeting: (time, speaker, text, effect).
    var pendingLines: [PendingLine] = []
    /// When the current (or last) meeting began, in game time.
    public internal(set) var meetingStart: Double = 0
    /// Lets the app rephrase AI lines (on-device model). Called with the line id and its template text.
    public var onAILine: ((Int, String, Int) -> Void)?

    public static let aiNames = ["Mochi", "Nori", "Pip", "Bao", "Juno", "Miso", "Pebble", "Tofu", "Wren", "Kelpie", "Sable"]

    public init(seed: UInt64, look: PlayerLook, roleChoice: RoleChoice = .random, aiCount: Int = 7, map: GameMap = .abyss) {
        self.map = map
        self.pathfinder = Pathfinder(map: map)
        self.rng = SeededRandom(seed: seed)
        phase = .intro(timeLeft: Tuning.introTime)
        var colors = PlayerColor.allCases.filter { $0 != look.color }
        colors.shuffle(using: &rng)
        var names = Self.aiNames
        names.shuffle(using: &rng)
        var hats = Hat.allCases
        var ps: [Player] = []
        ps.append(Player(id: 0, name: look.name, color: look.color, hat: look.hat, isHuman: true, role: .crew,
                         pos: map.spawns[0].center))
        for i in 1...aiCount {
            hats.shuffle(using: &rng)
            let hat: Hat = rng.chance(0.55) ? hats[0] : .none
            ps.append(Player(id: i, name: names[i - 1], color: colors[i - 1], hat: hat, isHuman: false, role: .crew,
                             pos: map.spawns[i % map.spawns.count].center))
        }
        let traitor: Int
        switch roleChoice {
        case .crew: traitor = Int.random(in: 1...aiCount, using: &rng)
        case .traitor: traitor = 0
        case .random: traitor = Int.random(in: 0...aiCount, using: &rng)
        }
        ps[traitor].role = .traitor
        players = ps
        let tasks = map.taskStations.map(\.id)
        for i in players.indices {
            var t = tasks
            t.shuffle(using: &rng)
            players[i].tasks = Array(t.prefix(Tuning.tasksPerCrew))
            players[i].killCooldown = Tuning.firstKillCooldown
            if !players[i].isHuman { brains[i] = Brain(id: i) }
        }
    }

    // MARK: Queries

    public var me: Player { players[you] }
    public var traitorID: Int { players.first(where: \.isTraitor)!.id }
    public var alive: [Player] { players.filter(\.alive) }

    public var totalTasks: Int { players.filter { $0.role == .crew }.reduce(0) { $0 + $1.tasks.count } }
    public var doneTasks: Int { players.filter { $0.role == .crew }.reduce(0) { $0 + $1.done.count } }
    public var taskProgress: Double { totalTasks == 0 ? 1 : Double(doneTasks) / Double(totalTasks) }

    public func sightRadius(of p: Player) -> Double {
        if !p.alive { return 99 }
        if p.isTraitor { return Tuning.traitorSight }
        return sabotage == .lights ? Tuning.lightsOutSight : Tuning.crewSight
    }

    /// Can player `a` see position `b` right now?
    public func canSee(_ a: Player, _ b: Vec2) -> Bool {
        Sight.sees(map, from: a.pos, to: b, radius: sightRadius(of: a))
    }

    public func drainEvents() -> [GameEvent] { defer { events.removeAll() }; return events }

    /// The station the human could use right now, if any.
    public var usableStation: Station? {
        guard case .playing = phase else { return nil }
        let p = me
        return map.stations.filter { canUse($0, by: p) }.min { $0.pos.center.distance(to: p.pos) < $1.pos.center.distance(to: p.pos) }
    }

    public func canUse(_ s: Station, by p: Player) -> Bool {
        let near: Bool
        if case .emergency = s.kind { near = distance(p.pos, to: map.meetingTable) <= Tuning.useRange }
        else { near = s.pos.center.distance(to: p.pos) <= Tuning.useRange }
        guard near else { return false }
        switch s.kind {
        case .task: return !p.isTraitor && p.tasks.contains(s.id) && !p.done.contains(s.id)
        case .emergency:
            if case .oxygen = sabotage { return false }
            return p.alive && p.emergencyLeft > 0
        case .fixLights: return p.alive && sabotage == .lights
        case .fixOxygen(let part):
            if p.alive, case .oxygen(_, let fixed) = sabotage { return !fixed[part] }
            return false
        }
    }

    /// An unreported body the human can report.
    public var reportableBody: Body? {
        guard case .playing = phase, me.alive else { return nil }
        return bodies.first { !$0.reported && $0.pos.distance(to: me.pos) <= Tuning.reportRange }
    }

    /// The crewmate the human traitor could take out right now.
    public var killTarget: Player? {
        guard case .playing = phase, me.alive, me.isTraitor, me.killCooldown <= 0 else { return nil }
        return players.filter { $0.alive && !$0.isTraitor && $0.pos.distance(to: me.pos) <= Tuning.killRange }
            .min { $0.pos.distance(to: me.pos) < $1.pos.distance(to: me.pos) }
    }

    public var canSabotage: Bool {
        guard case .playing = phase else { return false }
        return me.isTraitor && sabotage == .none && sabotageCooldown <= 0
    }

    // MARK: Human actions

    /// Finish a task (after its mini-game) or a sabotage fix.
    public func complete(station id: Int, by pid: Int? = nil) {
        let pid = pid ?? you
        let s = map.station(id)
        guard case .playing = phase, canUse(s, by: players[pid]) else { return }
        switch s.kind {
        case .task:
            players[pid].done.insert(id)
            events.append(.taskDone(player: pid))
            checkWin()
        case .fixLights:
            sabotage = .none
            events.append(.sabotageFixed)
        case .fixOxygen(let part):
            if case .oxygen(let t, var fixed) = sabotage {
                fixed[part] = true
                if fixed.allSatisfy({ $0 }) { sabotage = .none; events.append(.sabotageFixed) }
                else { sabotage = .oxygen(timeLeft: t, fixed: fixed) }
            }
        case .emergency:
            players[pid].emergencyLeft -= 1
            startMeeting(caller: pid, reason: .emergency)
        }
    }

    /// Debug and tests: call a meeting or end the game from outside.
    public func debugCallMeeting(caller: Int) { startMeeting(caller: caller, reason: .emergency) }
    public func debugFinish(_ w: Winner) { finish(w, w == .crew ? "Every task is done." : "Too few crew are left to stop the traitor.") }
    public func debugKill(_ victim: Int) { kill(victim, by: traitorID) }
    public func debugSabotage(_ k: SabotageKind) { startSabotage(k) }
    public func debugMove(_ id: Int, to v: Vec2) { players[id].pos = v }
    public func debugGiveTask(_ station: Int) { if !players[you].tasks.contains(station) { players[you].tasks.append(station) } }

    public func reportBody() {
        guard let b = reportableBody else { return }
        report(b.victim, by: you)
    }

    public func killNearest() {
        guard let t = killTarget else { return }
        kill(t.id, by: you)
    }

    public func triggerSabotage(_ kind: SabotageKind) {
        guard canSabotage else { return }
        startSabotage(kind)
    }

    // MARK: Step

    public func step(dt: Double) {
        time += dt
        switch phase {
        case .intro(let t):
            phase = t - dt <= 0 ? .playing : .intro(timeLeft: t - dt)
        case .playing:
            stepPlaying(dt)
        case .meeting(var m):
            m.elapsed += dt
            phase = .meeting(m)
            stepMeeting(dt)
        case .ejection(let e, let t):
            if t - dt <= 0 { endEjection() } else { phase = .ejection(e, timeLeft: t - dt) }
        case .over:
            break
        }
    }

    private func stepPlaying(_ dt: Double) {
        for i in players.indices {
            if players[i].killCooldown > 0 { players[i].killCooldown = max(0, players[i].killCooldown - dt) }
        }
        if sabotageCooldown > 0 && sabotage == .none { sabotageCooldown = max(0, sabotageCooldown - dt) }
        if case .oxygen(let t, let fixed) = sabotage {
            let left = t - dt
            if left <= 0 { finish(.traitor, "The oxygen ran out."); return }
            sabotage = .oxygen(timeLeft: left, fixed: fixed)
        }
        // Human movement.
        var dir = input
        if dir.length > 1 { dir = dir.normalized }
        move(you, by: dir * (Tuning.speed * dt), dt: dt)
        // AI.
        for id in brains.keys.sorted() {
            guard case .playing = phase else { return }
            think(id, dt: dt)
        }
    }

    func move(_ id: Int, by d: Vec2, dt: Double) {
        var p = players[id]
        let moving = d.length > 1e-6
        if moving {
            if abs(d.x) > 1e-6 { p.facing = d.x > 0 ? 1 : -1 }
            let ghost = !p.alive
            var np = p.pos
            np.x += d.x
            if ghost || fits(np) { p.pos.x = np.x } else { np.x = p.pos.x }
            np.y += d.y
            if ghost || fits(np) { p.pos.y = np.y }
            if ghost { p.pos = clampToMap(p.pos) }
            p.walkPhase += dt * 9
        }
        p.moving = moving
        players[id] = p
    }

    private func clampToMap(_ v: Vec2) -> Vec2 {
        Vec2(min(max(v.x, 0.5), Double(map.width) - 0.5), min(max(v.y, 0.5), Double(map.height) - 0.5))
    }

    /// Whether a player-sized box at `c` is clear of walls and props.
    func fits(_ c: Vec2) -> Bool {
        let r = Tuning.radius
        for (dx, dy) in [(-r, -r), (r, -r), (-r, r), (r, r)] {
            if !map.isWalkable(Vec2(c.x + dx, c.y + dy).tile) { return false }
        }
        return true
    }

    func distance(_ p: Vec2, to r: TileRect) -> Double {
        let cx = min(max(p.x, Double(r.x0)), Double(r.x1 + 1))
        let cy = min(max(p.y, Double(r.y0)), Double(r.y1 + 1))
        return Vec2(cx, cy).distance(to: p)
    }

    // MARK: Kills, reports, sabotage

    func kill(_ victim: Int, by killer: Int) {
        guard players[victim].alive, !players[victim].isTraitor else { return }
        let at = players[victim].pos
        // Witnesses: living crew AIs who can see the killer or the victim.
        for (id, brain) in brains where id != killer && id != victim && players[id].alive && !players[id].isTraitor {
            if canSee(players[id], players[killer].pos) || canSee(players[id], at) {
                brain.witnessed = (killer: killer, victim: victim, room: map.roomName(at: at.tile))
            }
        }
        players[victim].alive = false
        players[victim].working = false
        players[killer].killCooldown = Tuning.killCooldown
        // The killer steps onto the spot, like a lunge.
        if fits(at) { players[killer].pos = at }
        bodies.append(Body(victim: victim, killer: killer, pos: at, time: time))
        events.append(.kill(killer: killer, victim: victim))
        if victim == you { events.append(.youDied) }
        checkWin()
    }

    func report(_ victim: Int, by reporter: Int) {
        guard let i = bodies.firstIndex(where: { $0.victim == victim }) else { return }
        bodies[i].reported = true
        startMeeting(caller: reporter, reason: .body(victim: victim, room: map.roomName(at: bodies[i].pos.tile)))
    }

    func startSabotage(_ kind: SabotageKind) {
        switch kind {
        case .lights: sabotage = .lights
        case .oxygen: sabotage = .oxygen(timeLeft: Tuning.oxygenTime, fixed: [false, false])
        }
        sabotageCooldown = Tuning.sabotageCooldown
        events.append(.sabotage(kind))
        for b in brains.values { b.sabotageResponse = nil }
    }

    // MARK: Win checks

    func checkWin() {
        if case .over = phase { return }
        let traitorsAlive = players.filter { $0.alive && $0.isTraitor }.count
        let crewAlive = players.filter { $0.alive && !$0.isTraitor }.count
        if traitorsAlive == 0 { finish(.crew, "The traitor is gone."); return }
        if traitorsAlive >= crewAlive { finish(.traitor, "Too few crew are left to stop the traitor."); return }
        if doneTasks >= totalTasks { finish(.crew, "Every task is done.") }
    }

    func finish(_ w: Winner, _ reason: String) {
        phase = .over(w, reason: reason)
        for i in players.indices { players[i].working = false }
    }

    // MARK: Meetings

    func startMeeting(caller: Int, reason: MeetingReason) {
        guard case .playing = phase else { return }
        sabotage = .none
        meetingStart = time
        for i in players.indices { players[i].working = false; players[i].moving = false }
        phase = .meeting(Meeting(caller: caller, reason: reason))
        events.append(.meetingCalled(by: caller, reason: reason))
        planMeeting(caller: caller, reason: reason)
    }

    func say(_ speaker: Int, _ text: String, rephrase: Bool = false) {
        guard case .meeting(var m) = phase else { return }
        let line = MeetingLine(id: nextLineID, speaker: speaker, text: text, time: m.elapsed)
        nextLineID += 1
        m.lines.append(line)
        phase = .meeting(m)
        if rephrase && !players[speaker].isHuman { onAILine?(line.id, text, speaker) }
    }

    /// Replace an AI line's text (the app's on-device model rephrases lines after they appear).
    public func rephrase(line id: Int, to text: String) {
        guard case .meeting(var m) = phase, let i = m.lines.firstIndex(where: { $0.id == id }) else { return }
        m.lines[i].text = text
        phase = .meeting(m)
    }

    public func humanSay(_ statement: HumanStatement) {
        guard case .meeting = phase, me.alive else { return }
        let text: String
        switch statement {
        case .accuse(let t): text = "I think it's \(players[t].name)."
        case .vouch(let t): text = "\(players[t].name) was with me. They're fine."
        case .was(let room): text = "I was in \(room)."
        case .saw(let t, let room): text = "I saw \(players[t].name) in \(room)."
        }
        say(you, text)
        hear(statement, from: you)
    }

    public func humanVote(_ v: Vote) {
        guard case .meeting(var m) = phase, me.alive, m.votes[you] == nil else { return }
        m.votes[you] = v
        phase = .meeting(m)
        maybeEndMeeting()
    }

    func castVote(_ voter: Int, _ v: Vote) {
        guard case .meeting(var m) = phase, players[voter].alive, m.votes[voter] == nil else { return }
        m.votes[voter] = v
        phase = .meeting(m)
        maybeEndMeeting()
    }

    private func stepMeeting(_ dt: Double) {
        guard case .meeting(let m) = phase else { return }
        let due = pendingLines.filter { $0.at <= m.elapsed }
        pendingLines.removeAll { $0.at <= m.elapsed }
        for l in due {
            guard case .meeting = phase else { return }
            switch l.action {
            case .say(let text, _):
                guard players[l.speaker].alive else { continue }
                say(l.speaker, text, rephrase: l.rephrase)
                if !l.claims.isEmpty { hear(l.claims, from: l.speaker) }
            case .vote:
                castVote(l.speaker, aiVote(l.speaker))
            }
        }
        if case .meeting(let m2) = phase, m2.elapsed >= Meeting.duration { endMeeting() }
    }

    private func maybeEndMeeting() {
        guard case .meeting(let m) = phase else { return }
        let voters = players.filter(\.alive).map(\.id)
        if voters.allSatisfy({ m.votes[$0] != nil }) { endMeeting() }
    }

    private func endMeeting() {
        guard case .meeting(let m) = phase else { return }
        pendingLines.removeAll()
        var tally: [Int: Int] = [:]
        var skips = 0
        for p in players where p.alive {
            switch m.votes[p.id] ?? .skip {
            case .player(let t): tally[t, default: 0] += 1
            case .skip: skips += 1
            }
        }
        let top = tally.max { $0.value < $1.value }
        var ejected: Int?
        if let top, top.value > skips, tally.values.filter({ $0 == top.value }).count == 1 { ejected = top.key }
        let e = Ejection(ejected: ejected, wasTraitor: ejected.map { players[$0].isTraitor } ?? false, tally: tally, skips: skips)
        if let ejected {
            players[ejected].alive = false
            if ejected == you { events.append(.youDied) }
        }
        lastEjection = e
        phase = .ejection(e, timeLeft: Tuning.ejectionTime)
    }

    private func endEjection() {
        phase = .playing
        checkWin()
        guard case .playing = phase else { return }
        // Everyone back to the table; bodies are cleared away.
        bodies.removeAll()
        var spawn = 0
        for i in players.indices where players[i].alive {
            players[i].pos = map.spawns[spawn % map.spawns.count].center
            spawn += 1
            players[i].killCooldown = max(players[i].killCooldown, Tuning.firstKillCooldown)
        }
        for b in brains.values { b.afterMeeting() }
    }
}

public enum HumanStatement: Sendable, Equatable {
    case accuse(Int)
    case vouch(Int)
    case was(String)
    case saw(Int, String)
}

struct PendingLine {
    enum Action { case say(String, effect: HumanStatement?), vote }
    let at: Double
    let speaker: Int
    let action: Action
    var claims: [Claim] = []
    /// Whether the app may restyle the wording (never for accusations).
    var rephrase = false
}
