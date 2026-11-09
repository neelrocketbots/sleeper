import SleeperCore
import SwiftUI

struct LobbyView: View {
    let controller: GameController
    var body: some View {
        let look = controller.look
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.07, blue: 0.12), Color(red: 0.01, green: 0.03, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
            BubbleField()
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("SLEEPER").font(Theme.title(40)).tracking(6).foregroundStyle(Theme.ink)
                    Text("Someone in The Abyss isn't who they seem.").font(Theme.body(13)).foregroundStyle(Theme.soft)
                }
                HStack(alignment: .center, spacing: 28) {
                    ZStack {
                        Circle().fill(Theme.color(look.color).opacity(0.18)).frame(width: 150, height: 150).blur(radius: 18)
                        Portrait(color: look.color, hat: look.hat, scale: 7)
                    }
                    .frame(width: 160, height: 160)
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Colour").font(Theme.body(11, .semibold)).foregroundStyle(Theme.faint); Spacer(); Hint(key: "← →", text: look.color.name) }
                            HStack(spacing: 5) {
                                ForEach(PlayerColor.allCases, id: \.self) { c in
                                    RoundedRectangle(cornerRadius: 4).fill(Theme.color(c)).frame(width: 18, height: 18)
                                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white, lineWidth: c == look.color ? 2 : 0))
                                        .onTapGesture { controller.look.color = c; controller.saveLook() }
                                }
                            }
                        }
                        HStack { Text("Hat").font(Theme.body(11, .semibold)).foregroundStyle(Theme.faint); Spacer(); Hint(key: "↑ ↓", text: look.hat.name) }
                        HStack { Text("Role").font(Theme.body(11, .semibold)).foregroundStyle(Theme.faint); Spacer(); Hint(key: "R", text: controller.roleChoice.name) }
                        HStack { Text("Crew voices").font(Theme.body(11, .semibold)).foregroundStyle(Theme.faint); Spacer()
                            Text(controller.voice.available ? "On-device model" : "Built-in lines").font(Theme.body(11.5)).foregroundStyle(Theme.soft) }
                    }
                    .frame(width: 290)
                    .padding(14)
                    .panel()
                }
                HStack(spacing: 6) {
                    KeyCap("Space")
                    Text("Dive in").font(Theme.body(14, .bold)).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .panel(tint: Theme.accent, radius: 20)
                .onTapGesture { controller.startGame() }
                HStack(spacing: 14) {
                    Hint(key: "WASD", text: "swim")
                    Hint(key: "E", text: "use")
                    Hint(key: "R", text: "report")
                    Hint(key: "Q", text: "take out")
                    Hint(key: "Tab", text: "map")
                    Hint(key: "Esc", text: "fold")
                }
            }
        }
    }
}

/// Slow rising bubbles, behind the lobby.
struct BubbleField: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<26 {
                    let seed = Double(i) * 12.9898
                    let x = (sin(seed) * 0.5 + 0.5) * size.width + sin(t * 0.6 + seed) * 8
                    let speed = 14 + (cos(seed) * 0.5 + 0.5) * 22
                    let y = size.height - ((t * speed + seed * 40).truncatingRemainder(dividingBy: size.height + 40)) + 20
                    let r = 1.5 + (sin(seed * 3) * 0.5 + 0.5) * 3
                    g.stroke(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.18)), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
