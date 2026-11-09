import AppKit
import Observation
import SleeperCore
import SpriteKit

/// A task mini-game in progress.
struct MiniGameState: Equatable {
    let station: Int
    let title: String
    let game: MiniGame
    var progress: Double = 0
    var holding = false
    // Sequence
    var sequence: [Direction] = []
    var index = 0
    var mistake = 0.0
    // Timing
    var needle = 0.0
    var needleSpeed = 0.9
    var needleDir = 1.0
    var zone = 0.4...0.58
    var hits = 0
    var flash = 0.0
    var finished = 0.0

    enum Direction: CaseIterable { case up, down, left, right
        var symbol: String { switch self { case .up: "arrow.up"; case .down: "arrow.down"; case .left: "arrow.left"; case .right: "arrow.right" } }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let tone: Tone
    var left: Double
    enum Tone { case info, alert, good }
}

/// Owns the current game, turns key presses into game input, and publishes what the SwiftUI overlays show.
@MainActor @Observable final class GameController {
    enum Screen: Equatable { case lobby, game }

    var screen: Screen = .lobby
    var look: PlayerLook
    var roleChoice: RoleChoice = .random
    private(set) var game: Game?
    /// Bumped at ~10 Hz so SwiftUI re-reads the game.
    private(set) var revision = 0
    var miniGame: MiniGameState?
    var toasts: [Toast] = []
    var showMap = false
    var paused = false
    /// Scripted snapshots: never pause, and draw overlays without an opaque backdrop behind the scene.
    var snapshotMode = false
    // Meeting UI
    var meetingSelection = 0
    var claimRoom = 0
    /// The meeting's text box is open: keys go to it, not the game.
    var chatOpen = false
    var chatText = ""
    var saidThisMeeting: Set<String> = []

    private var keys: Set<UInt16> = []
    private var accumulator = 0.0
    private var hudTimer = 0.0
    private let step = 1.0 / 30
    let voice = AIVoice()

    private var clock: Timer?
    private var lastClock: Double?

    init() {
        let d = UserDefaults.standard
        let color = PlayerColor(rawValue: d.object(forKey: "color") as? Int ?? 0) ?? .coral
        let hat = Hat(rawValue: d.object(forKey: "hat") as? Int ?? 1) ?? .captain
        look = PlayerLook(color: color, hat: hat, name: color.name)
        // The game clock is independent of rendering, so the game keeps time even if frames stall.
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.clockTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        clock = t
    }

    private func clockTick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(1.0 / 15, lastClock.map { now - $0 } ?? 0)
        lastClock = now
        tick(dt: dt)
    }

    func saveLook() {
        look.name = look.color.name
        UserDefaults.standard.set(look.color.rawValue, forKey: "color")
        UserDefaults.standard.set(look.hat.rawValue, forKey: "hat")
    }

    // MARK: Game lifecycle

    weak var skView: SKView?
    /// Debug: start games from this seed instead of a random one.
    var debugSeed: UInt64?

    func startGame(seed: UInt64? = nil) {
        saveLook()
        let g = Game(seed: seed ?? debugSeed ?? UInt64.random(in: 1...UInt64.max), look: look, roleChoice: roleChoice)
        g.onAILine = { [weak self] id, text, speaker in self?.voice.rephrase(line: id, text: text, speaker: speaker, controller: self) }
        game = g
        miniGame = nil
        toasts = []
        showMap = false
        keys = []
        screen = .game
        revision += 1
    }

    func backToLobby() {
        game = nil
        miniGame = nil
        screen = .lobby
        revision += 1
    }

    func rephrased(line id: Int, to text: String) {
        game?.rephrase(line: id, to: text)
        revision += 1
    }

    // MARK: Clock

    func tick(dt: Double) {
        guard let game, !paused else { return }
        game.input = (miniGame == nil && !showMap) ? moveInput() : .zero
        accumulator += dt
        while accumulator >= step {
            accumulator -= step
            let wasMeeting: Bool = { if case .meeting = game.phase { return true }; return false }()
            game.step(dt: step)
            if case .meeting = game.phase, !wasMeeting { enterMeeting() }
            tickMiniGame(step)
        }
        for e in game.drainEvents() { handle(e) }
        for i in toasts.indices { toasts[i].left -= dt }
        toasts.removeAll { $0.left <= 0 }
        hudTimer -= dt
        if hudTimer <= 0 { hudTimer = 0.1; revision += 1 }
    }

    private func moveInput() -> Vec2 {
        var v = Vec2.zero
        if keys.contains(13) || keys.contains(126) { v.y -= 1 }
        if keys.contains(1) || keys.contains(125) { v.y += 1 }
        if keys.contains(0) || keys.contains(123) { v.x -= 1 }
        if keys.contains(2) || keys.contains(124) { v.x += 1 }
        return v
    }

    private func handle(_ e: GameEvent) {
        guard let game else { return }
        switch e {
        case .sabotage(.lights): toast("The lights are out. Restore them in Thermal Vent.", .alert)
        case .sabotage(.oxygen): toast("Oxygen leak! Seal both consoles: Pressure Lock and Ballast Tanks.", .alert)
        case .sabotageFixed: toast("Fixed.", .good)
        case .taskDone(let p) where p == game.you: toast("Task done.", .good)
        case .youDied:
            miniGame = nil
            if case .ejection = game.phase {} else if !game.me.isTraitor {
                toast("You were taken. Keep doing your tasks as a ghost.", .alert, 5)
            }
        case .meetingCalled:
            miniGame = nil
        default: break
        }
    }

    func toast(_ text: String, _ tone: Toast.Tone = .info, _ seconds: Double = 3.5) {
        toasts.append(Toast(text: text, tone: tone, left: seconds))
        if toasts.count > 3 { toasts.removeFirst() }
    }

    func sendChat() {
        let text = chatText
        chatText = ""
        chatOpen = false
        guard let game, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        game.humanSay(.free(text))
        revision += 1
    }

    func closeChat() { chatOpen = false; revision += 1 }

    private func enterMeeting() {
        chatOpen = false
        chatText = ""
        miniGame = nil
        showMap = false
        meetingSelection = 0
        saidThisMeeting = []
        if let game, let r = game.map.room(at: game.me.pos.tile) { claimRoom = r.id }
    }

    // MARK: Keys

    /// Returns true when the key was used.
    func key(down: Bool, code: UInt16, repeat isRepeat: Bool) -> Bool {
        if chatOpen { return false }  // typing a message
        if down { keys.insert(code) } else { keys.remove(code) }
        switch screen {
        case .lobby: return down ? lobbyKey(code) : true
        case .game: return gameKey(down: down, code: code, isRepeat: isRepeat)
        }
    }

    func releaseAllKeys() { keys.removeAll() }

    private func lobbyKey(_ code: UInt16) -> Bool {
        let colors = PlayerColor.allCases, hats = Hat.allCases, roles = RoleChoice.allCases
        switch code {
        case 123, 0: look.color = colors[(look.color.rawValue + colors.count - 1) % colors.count]
        case 124, 2: look.color = colors[(look.color.rawValue + 1) % colors.count]
        case 126, 13: look.hat = hats[(look.hat.rawValue + hats.count - 1) % hats.count]
        case 125, 1: look.hat = hats[(look.hat.rawValue + 1) % hats.count]
        case 15: roleChoice = roles[((roles.firstIndex(of: roleChoice) ?? 0) + 1) % roles.count]
        case 49, 36: startGame()
        default: return false
        }
        saveLook()
        return true
    }

    private func gameKey(down: Bool, code: UInt16, isRepeat: Bool) -> Bool {
        guard let game else { return false }
        if code == 53 { return false }  // Esc: the island folds (handled by the island)
        if let mg = miniGame { return miniGameKey(down: down, code: code, mg: mg) }
        switch game.phase {
        case .intro: return true
        case .over:
            if down && (code == 49 || code == 36) { startGame() }
            if down && code == 37 { backToLobby() }  // L
            return true
        case .ejection: return true
        case .meeting: return down ? meetingKey(code) : true
        case .playing: break
        }
        guard down, !isRepeat else { return [13, 0, 1, 2, 123, 124, 125, 126].contains(code) }
        switch code {
        case 14, 49:  // E / Space: use
            if let s = game.usableStation { use(s) }
        case 15: game.reportBody()          // R
        case 12: game.killNearest()          // Q
        case 18: game.triggerSabotage(.lights)  // 1
        case 19: game.triggerSabotage(.oxygen)  // 2
        case 48, 46: showMap.toggle()       // Tab / M
        default: return [13, 0, 1, 2, 123, 124, 125, 126].contains(code)
        }
        revision += 1
        return true
    }

    private func use(_ s: Station) {
        guard let game else { return }
        switch s.kind {
        case .emergency:
            game.complete(station: s.id)
        case .task(let name, let kind):
            miniGame = makeMiniGame(station: s.id, title: name, kind)
        case .fixLights, .fixOxygen:
            miniGame = MiniGameState(station: s.id, title: s.name, game: .hold)
        }
    }

    // MARK: Mini-games

    private func makeMiniGame(station: Int, title: String, _ kind: MiniGame) -> MiniGameState {
        var m = MiniGameState(station: station, title: title, game: kind)
        switch kind {
        case .hold: break
        case .sequence: m.sequence = (0..<5).map { _ in MiniGameState.Direction.allCases.randomElement()! }
        case .timing: m.zone = Self.randomZone(); m.needleSpeed = Double.random(in: 0.8...1.1)
        }
        return m
    }

    private static func randomZone() -> ClosedRange<Double> { let a = Double.random(in: 0.1...0.72); return a...(a + 0.18) }

    private func tickMiniGame(_ dt: Double) {
        guard var m = miniGame, let game else { return }
        guard case .playing = game.phase else { miniGame = nil; return }
        if m.finished > 0 {
            m.finished -= dt
            if m.finished <= 0 { game.complete(station: m.station); miniGame = nil; return }
            miniGame = m
            return
        }
        // Walked away or the station stopped being usable (a fix finished elsewhere).
        if !game.canUse(game.map.station(m.station), by: game.me) { miniGame = nil; return }
        m.mistake = max(0, m.mistake - dt)
        m.flash = max(0, m.flash - dt)
        switch m.game {
        case .hold:
            let holding = keys.contains(14) || keys.contains(49)
            m.holding = holding
            let duration = m.title.hasPrefix("Restore") || m.title.hasPrefix("Seal") ? 1.4 : 2.2
            m.progress = holding ? min(1, m.progress + dt / duration) : max(0, m.progress - dt * 0.4)
            if m.progress >= 1 { m.finished = 0.35 }
        case .sequence:
            m.progress = Double(m.index) / Double(m.sequence.count)
        case .timing:
            m.needle += m.needleDir * m.needleSpeed * dt
            if m.needle >= 1 { m.needle = 1; m.needleDir = -1 }
            if m.needle <= 0 { m.needle = 0; m.needleDir = 1 }
            m.progress = Double(m.hits) / 3
        }
        miniGame = m
    }

    private func miniGameKey(down: Bool, code: UInt16, mg: MiniGameState) -> Bool {
        guard down, var m = miniGame, m.finished <= 0 else { return true }
        switch m.game {
        case .hold: break
        case .sequence:
            let map: [UInt16: MiniGameState.Direction] = [126: .up, 13: .up, 125: .down, 1: .down, 123: .left, 0: .left, 124: .right, 2: .right]
            if let d = map[code] {
                if m.sequence[m.index] == d {
                    m.index += 1
                    if m.index == m.sequence.count { m.progress = 1; m.finished = 0.4 }
                } else {
                    m.index = 0
                    m.mistake = 0.4
                }
            }
        case .timing:
            if code == 49 || code == 14 {
                if m.zone.contains(m.needle) {
                    m.hits += 1
                    m.flash = 0.25
                    m.zone = Self.randomZone()
                    m.needleSpeed += 0.25
                    if m.hits >= 3 { m.progress = 1; m.finished = 0.4 }
                } else {
                    m.mistake = 0.4
                    m.hits = max(0, m.hits - 1)
                }
            }
        }
        miniGame = m
        return true
    }

    func closeMiniGame() { miniGame = nil }

    func tabMap(_ on: Bool) { showMap = on; revision += 1 }

    /// Debug: open a station's mini-game wherever the player is.
    func debugOpenMiniGame(_ station: Int) {
        guard let game, case .task(let name, let kind) = game.map.station(station).kind else { return }
        miniGame = makeMiniGame(station: station, title: name, kind)
    }

    // MARK: Meeting

    var meetingPlayers: [Player] { game?.players ?? [] }

    private func meetingKey(_ code: UInt16) -> Bool {
        guard let game, case .meeting(let m) = game.phase else { return true }
        // T opens the text box; while it's open, keys belong to it.
        if code == 17, game.me.alive { chatOpen = true; revision += 1; return true }
        let n = game.players.count
        let sel = game.players[meetingSelection % n]
        let canAct = game.me.alive && m.votes[game.you] == nil
        let rooms = game.map.rooms
        switch code {
        case 123: meetingSelection = (meetingSelection + n - 1) % n
        case 124: meetingSelection = (meetingSelection + 1) % n
        case 126: meetingSelection = (meetingSelection + n - 4) % n
        case 125: meetingSelection = (meetingSelection + 4) % n
        case 33: claimRoom = (claimRoom + rooms.count - 1) % rooms.count  // [
        case 30: claimRoom = (claimRoom + 1) % rooms.count                // ]
        case 0:  // A: accuse
            if game.me.alive, sel.alive, sel.id != game.you, !saidThisMeeting.contains("a\(sel.id)") {
                game.humanSay(.accuse(sel.id)); saidThisMeeting.insert("a\(sel.id)")
            }
        case 9:  // V: vouch
            if game.me.alive, sel.alive, sel.id != game.you, !saidThisMeeting.contains("v\(sel.id)") {
                game.humanSay(.vouch(sel.id)); saidThisMeeting.insert("v\(sel.id)")
            }
        case 8:  // C: claim where you were
            if game.me.alive, !saidThisMeeting.contains("c") {
                game.humanSay(.was(rooms[claimRoom].name)); saidThisMeeting.insert("c")
            }
        case 36, 49:  // Enter / Space: vote for the selected player
            if canAct, sel.alive, sel.id != game.you { game.humanVote(.player(sel.id)) }
        case 1:  // S: skip
            if canAct { game.humanVote(.skip) }
        default: break
        }
        revision += 1
        return true
    }
}
