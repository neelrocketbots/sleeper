import SleeperCore
import SwiftUI

/// Everything drawn over the game: role reveal, HUD, mini-games, map, meeting, ejection, results.
struct GameOverlays: View {
    let controller: GameController
    let game: Game

    var body: some View {
        ZStack {
            switch game.phase {
            case .intro: RoleReveal(rev: controller.revision, game: game)
            case .playing:
                HUDView(rev: controller.revision, controller: controller, game: game)
                if controller.showMap { MapOverlay(rev: controller.revision, game: game) }
                if let mg = controller.miniGame { MiniGameView(state: mg) }
            case .meeting(let m): MeetingView(rev: controller.revision, controller: controller, game: game, meeting: m)
            case .ejection(let e, _): EjectionView(rev: controller.revision, game: game, ejection: e)
            case .over(let w, let reason): GameOverView(rev: controller.revision, game: game, winner: w, reason: reason)
            }
            VStack(spacing: 6) {
                ForEach(controller.toasts) { t in
                    Text(t.text).font(Theme.body(12.5, .semibold))
                        .foregroundStyle(t.tone == .alert ? Theme.alert : (t.tone == .good ? Theme.good : Theme.ink))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .panel(tint: t.tone == .alert ? Theme.alert : nil, radius: 10)
                        .transition(.opacity)
                }
                Spacer()
            }
            .padding(.top, 10)
            .allowsHitTesting(false)
        }
    }
}

struct RoleReveal: View {
    var rev = 0
    let game: Game
    var body: some View {
        let me = game.me
        ZStack {
            Color.black.opacity(0.7)
            VStack(spacing: 14) {
                Text(me.isTraitor ? "You are the TRAITOR" : "You are CREW")
                    .font(Theme.title(30)).foregroundStyle(me.isTraitor ? Theme.alert : Theme.good)
                Text(me.isTraitor ? "Take out the crew without being caught. Q takes out, 1 and 2 sabotage."
                                  : "Finish your tasks and find the traitor. One of these seven is lying.")
                    .font(Theme.body(13)).foregroundStyle(Theme.soft)
                HStack(spacing: 10) {
                    ForEach(game.players.filter { me.isTraitor ? !$0.isTraitor : $0.id != me.id }) { p in
                        VStack(spacing: 3) {
                            Portrait(color: p.color, hat: p.hat, scale: 3)
                            Text(p.name).font(Theme.body(10.5)).foregroundStyle(Theme.soft)
                        }
                    }
                }
            }
        }
    }
}

struct HUDView: View {
    var rev = 0
    let controller: GameController
    let game: Game
    var body: some View {
        let me = game.me
        VStack {
            HStack(alignment: .top) {
                // Task list.
                VStack(alignment: .leading, spacing: 4) {
                    Text(me.isTraitor ? "Fake tasks" : (me.alive ? "Tasks" : "Tasks (ghost)"))
                        .font(Theme.body(11, .bold)).foregroundStyle(Theme.faint)
                    ForEach(me.tasks, id: \.self) { sid in
                        let s = game.map.station(sid)
                        let done = me.done.contains(sid)
                        HStack(spacing: 6) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 9))
                                .foregroundStyle(done ? Theme.good : Theme.faint)
                            Text("\(game.map.rooms[s.room].name): \(s.name)").font(Theme.body(11))
                                .foregroundStyle(done ? Theme.faint : Theme.ink).strikethrough(done)
                        }
                    }
                }
                .padding(10)
                .panel(radius: 12)
                Spacer()
                if game.sabotage.isActive { SabotageCard(rev: rev, game: game) }
            }
            Spacer()
            HStack(alignment: .bottom) {
                Spacer()
                ActionBar(rev: rev, game: game)
            }
        }
        .padding(10)
    }
}

struct SabotageCard: View {
    var rev = 0
    let game: Game
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch game.sabotage {
            case .lights:
                Text("Lights out").font(Theme.body(12, .bold)).foregroundStyle(Theme.alert)
                Text("Restore them at the panel in Thermal Vent").font(Theme.body(11)).foregroundStyle(Theme.soft)
            case .oxygen(let t, let fixed):
                Text("Oxygen leak · \(Int(t.rounded(.up)))s").font(Theme.body(12, .bold)).foregroundStyle(Theme.alert).monospacedDigit()
                Text("\(fixed[0] ? "✓" : "○") Pressure Lock console").font(Theme.body(11)).foregroundStyle(Theme.soft)
                Text("\(fixed[1] ? "✓" : "○") Ballast Tanks console").font(Theme.body(11)).foregroundStyle(Theme.soft)
            case .none: EmptyView()
            }
        }
        .padding(10)
        .panel(tint: Theme.alert, radius: 12)
    }
}

/// The context actions, bottom right.
struct ActionBar: View {
    var rev = 0
    let game: Game
    var body: some View {
        let me = game.me
        HStack(spacing: 8) {
            if let s = game.usableStation {
                ActionButton(key: "E", label: s.name, tint: Theme.good)
            }
            if game.reportableBody != nil {
                ActionButton(key: "R", label: "Report body", tint: Theme.alert)
            }
            if me.isTraitor && me.alive {
                ActionButton(key: "Q", label: me.killCooldown > 0 ? "Take out \(Int(me.killCooldown.rounded(.up)))s" : "Take out",
                             tint: Theme.alert, enabled: game.killTarget != nil)
                ActionButton(key: "1", label: "Lights", tint: Theme.gold, enabled: game.canSabotage)
                ActionButton(key: "2", label: "Oxygen", tint: Theme.gold, enabled: game.canSabotage)
            }
            ActionButton(key: "Tab", label: "Map", tint: nil)
        }
    }
}

struct ActionButton: View {
    let key: String
    let label: String
    let tint: Color?
    var enabled = true
    var body: some View {
        HStack(spacing: 6) {
            KeyCap(key)
            Text(label).font(Theme.body(12, .semibold)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .panel(tint: enabled ? tint : nil, radius: 10)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Tab: the whole station, with you, your tasks and any sabotage consoles.
struct MapOverlay: View {
    var rev = 0
    let game: Game
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            Canvas { g, size in
                let map = game.map
                let s = min(size.width / CGFloat(map.width), size.height / CGFloat(map.height)) * 0.92
                let ox = (size.width - CGFloat(map.width) * s) / 2, oy = (size.height - CGFloat(map.height) * s) / 2
                func rect(_ r: TileRect) -> CGRect {
                    CGRect(x: ox + CGFloat(r.x0) * s, y: oy + CGFloat(r.y0) * s, width: CGFloat(r.width) * s, height: CGFloat(r.height) * s)
                }
                for c in map.corridors { g.fill(Path(rect(c)), with: .color(Color(red: 0.6, green: 0.85, blue: 1).opacity(0.18))) }
                for r in map.rooms {
                    let d = CGRect(x: ox + (r.center.x - r.radius) * s, y: oy + (r.center.y - r.radius) * s, width: r.radius * 2 * s, height: r.radius * 2 * s)
                    g.fill(Path(ellipseIn: d), with: .color(.white.opacity(0.16)))
                    g.stroke(Path(ellipseIn: d), with: .color(.white.opacity(0.3)), lineWidth: 1)
                    g.draw(Text(r.name).font(Theme.body(10, .semibold)).foregroundStyle(Theme.soft), at: CGPoint(x: d.midX, y: d.minY + 12))
                }
                let me = game.me
                for sid in me.tasks where !me.done.contains(sid) && !me.isTraitor {
                    let p = game.map.station(sid).pos.center
                    g.fill(Path(ellipseIn: CGRect(x: ox + p.x * s - 3, y: oy + p.y * s - 3, width: 6, height: 6)), with: .color(Theme.gold))
                }
                for st in map.stations {
                    var on = false
                    if case .fixLights = st.kind, game.sabotage == .lights { on = true }
                    if case .fixOxygen(let part) = st.kind, case .oxygen(_, let fixed) = game.sabotage, !fixed[part] { on = true }
                    if on { g.fill(Path(ellipseIn: CGRect(x: ox + st.pos.center.x * s - 4, y: oy + st.pos.center.y * s - 4, width: 8, height: 8)), with: .color(Theme.alert)) }
                }
                let p = me.pos
                g.fill(Path(ellipseIn: CGRect(x: ox + p.x * s - 5, y: oy + p.y * s - 5, width: 10, height: 10)), with: .color(Theme.color(me.color)))
                g.stroke(Path(ellipseIn: CGRect(x: ox + p.x * s - 5, y: oy + p.y * s - 5, width: 10, height: 10)), with: .color(.white), lineWidth: 1.5)
            }
            .padding(24)
        }
    }
}
