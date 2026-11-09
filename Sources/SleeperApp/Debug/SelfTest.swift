import AppKit
import SleeperCore

/// `Sleeper --selftest`: plays through the real key path (the same calls the key monitor makes) and checks the
/// results: lobby choices, swimming, a hold task, a sequence task, reporting a body, voting. Prints PASS/FAIL lines.
@MainActor final class SelfTest {
    let c: GameController
    private var steps: [(Double, () -> Void)] = []
    private var failures = 0
    private var t = 0.5

    init(controller: GameController) { c = controller }

    private func at(_ dt: Double, _ f: @escaping () -> Void) { t += dt; steps.append((t, f)) }
    private func press(_ code: UInt16) { _ = c.key(down: true, code: code, repeat: false); _ = c.key(down: false, code: code, repeat: false) }
    private func check(_ ok: Bool, _ what: String) {
        print("\(ok ? "PASS" : "FAIL")  \(what)")
        if !ok { failures += 1 }
    }

    func run() {
        var startColor = c.look.color
        var startPos = Vec2.zero
        var taskStation = -1
        at(0) { startColor = self.c.look.color; self.press(124) }
        at(0.1) { self.check(self.c.look.color != startColor, "→ changes colour in the lobby") }
        at(0.1) { self.c.roleChoice = .crew; self.c.debugSeed = 11; self.press(49) }
        at(0.2) { self.check(self.c.screen == .game && self.c.game != nil, "Space starts a game") }
        at(4.0) {
            guard let g = self.c.game else { return }
            if case .playing = g.phase { self.check(true, "role reveal ends and play starts") } else { self.check(false, "role reveal ends") }
            startPos = g.me.pos
            _ = self.c.key(down: true, code: 2, repeat: false)  // hold D
        }
        at(0.8) {
            _ = self.c.key(down: false, code: 2, repeat: false)
            guard let g = self.c.game else { return }
            self.check(g.me.pos.x > startPos.x + 1, "holding D swims right (\(String(format: "%.1f", g.me.pos.x - startPos.x)) tiles)")
        }
        // A hold task: stand at it, press E, hold E.
        at(0.2) {
            guard let g = self.c.game else { return }
            taskStation = g.me.tasks.first { if case .task(_, .hold) = g.map.station($0).kind { return true }; return false }
                ?? g.me.tasks[0]
            g.debugMove(0, to: g.map.station(taskStation).pos.center)
        }
        at(0.2) {
            guard let g = self.c.game else { return }
            self.check(g.usableStation?.id == taskStation, "the task's station is usable when standing at it")
            self.press(14)
            self.check(self.c.miniGame != nil, "E opens the mini-game")
            _ = self.c.key(down: true, code: 14, repeat: false)
        }
        at(3.5) {
            _ = self.c.key(down: false, code: 14, repeat: false)
            guard let g = self.c.game else { return }
            let kind = g.map.station(taskStation).kind
            if case .task(_, .hold) = kind {
                self.check(g.me.done.contains(taskStation), "holding E finishes a hold task")
            } else {
                self.check(true, "(no hold task assigned; skipped)")
            }
            self.c.closeMiniGame()
        }
        // A sequence task: give one and press its arrows.
        at(0.2) {
            guard let g = self.c.game, let s = g.map.taskStations.first(where: { if case .task(_, .sequence) = $0.kind { return !g.me.done.contains($0.id) }; return false }) else { return }
            g.debugGiveTask(s.id)
            g.debugMove(0, to: s.pos.center)
            taskStation = s.id
        }
        at(0.2) {
            self.press(14)
            guard let m = self.c.miniGame else { self.check(false, "sequence mini-game opens"); return }
            let codes: [MiniGameState.Direction: UInt16] = [.up: 126, .down: 125, .left: 123, .right: 124]
            for d in m.sequence { self.press(codes[d]!) }
        }
        at(0.8) {
            guard let g = self.c.game else { return }
            self.check(g.me.done.contains(taskStation), "pressing the arrows in order finishes a sequence task")
        }
        // A body: report it with R.
        at(0.2) {
            guard let g = self.c.game else { return }
            let victim = g.players.first { !$0.isTraitor && !$0.isHuman && $0.alive }!.id
            g.debugKill(victim)
            g.debugMove(0, to: g.bodies[0].pos + Vec2(0.4, 0))
        }
        at(0.2) {
            guard let g = self.c.game else { return }
            self.check(g.reportableBody != nil, "a body nearby can be reported")
            self.press(15)
            if case .meeting = g.phase { self.check(true, "R calls a meeting") } else { self.check(false, "R calls a meeting") }
        }
        at(6) {
            guard let g = self.c.game, case .meeting(let m) = g.phase else { self.check(false, "meeting still running"); return }
            self.check(!m.lines.isEmpty, "AI crew speak in the meeting (\(m.lines.count) lines)")
            self.press(8)  // C: claim a room
            self.press(1)  // S: skip
        }
        at(0.3) {
            guard let g = self.c.game, case .meeting(let m) = g.phase else { return }
            self.check(m.votes[g.you] == .skip, "S casts a skip vote")
            self.check(m.lines.contains { $0.speaker == g.you }, "C says where you were")
        }
        // Poll: the meeting must end within its 75 s (another meeting may start later, which is fine).
        var ended = false
        for _ in 0..<85 {
            at(1) {
                guard !ended, let g = self.c.game else { return }
                if case .meeting = g.phase { return }
                ended = true
            }
        }
        at(0.1) {
            self.check(ended, "the meeting ends and the game moves on")
            print(self.failures == 0 ? "ALL PASSED" : "\(self.failures) FAILED")
            exit(self.failures == 0 ? 0 : 1)
        }
        for (time, f) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: f) }
    }
}
