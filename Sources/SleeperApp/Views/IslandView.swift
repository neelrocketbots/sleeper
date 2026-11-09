import NotchKit
import SleeperCore
import SpriteKit
import SwiftUI

/// The floating island: NotchKit chrome, a header band with the HUD, the game below.
struct IslandView: View {
    let island: IslandModel
    let controller: GameController
    @State private var gripHover = false

    var body: some View {
        // Docked: the notch's own shape (shoulders flaring into the menu bar). Floating: a card.
        let shape = island.docked ? AnyShape(NotchShape(shoulder: 12, bottomRadius: NotchFloat.cornerRadius))
                                  : AnyShape(NotchPillShape(cornerRadius: NotchFloat.cornerRadius))
        let band = max(32, island.geometry.notch.height)
        ZStack {
            // One solid shape: the band and the game share the island's outer corners, with no gap between them.
            if controller.snapshotMode {
                // Snapshots composite the SpriteKit frame underneath, so only the band is filled here.
                VStack(spacing: 0) { Color.black.frame(height: band); Color.clear }.clipShape(shape)
            } else {
                shape.fill(Color.black).modifier(NotchFloatShadow(on: true))
            }
            if island.collapsed {
                CollapsedBand(controller: controller, notchWidth: island.geometry.notch.width)
                    .clipShape(shape)
            } else {
            VStack(spacing: 0) {
                ZStack {
                    NotchMoveArea(driver: island)
                    HeaderBand(controller: controller)
                        .allowsHitTesting(false)
                    NotchGripDots(lit: gripHover || island.isMoving)
                        .frame(width: NotchGrip.hitSize.width, height: NotchGrip.hitSize.height)
                        .contentShape(Rectangle())
                        .onHover { gripHover = $0 }
                }
                .frame(height: band)
                GameArea(controller: controller)
            }
            .clipShape(shape)
            }
            shape.stroke(island.dockPreview ? Theme.accent.opacity(0.9) : .white.opacity(0.08), lineWidth: island.dockPreview ? 2 : 1)
                .allowsHitTesting(false)
        }
        .frame(width: island.size.width, height: island.size.height)
        .padding(NotchFloat.margin)
        .environment(\.colorScheme, .dark)
    }
}

/// The island folded into the notch: your axolotl on the left of the notch, the state of play on the right.
struct CollapsedBand: View {
    let controller: GameController
    let notchWidth: Double
    var body: some View {
        let _ = controller.revision
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Portrait(color: controller.look.color, hat: controller.look.hat, scale: 1.1)
                Text("SLEEPER").font(.system(size: 9.5, weight: .heavy, design: .rounded)).tracking(1.2).foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            Group {
                if let g = controller.game {
                    if case .oxygen(let t, _) = g.sabotage {
                        Text("O₂ \(Int(t.rounded(.up)))s").foregroundStyle(Theme.alert)
                    } else if case .meeting = g.phase {
                        Text("Meeting").foregroundStyle(Theme.gold)
                    } else if case .over = g.phase {
                        Text("Game over").foregroundStyle(Theme.soft)
                    } else {
                        HStack(spacing: 4) {
                            Circle().trim(from: 0, to: g.taskProgress).stroke(Theme.good, lineWidth: 2.5)
                                .rotationEffect(.degrees(-90)).frame(width: 12, height: 12)
                                .background(Circle().stroke(.white.opacity(0.15), lineWidth: 2.5))
                            Text("\(Int(g.taskProgress * 100))%").foregroundStyle(Theme.soft)
                        }
                    }
                } else {
                    Text("Play").foregroundStyle(Theme.soft)
                }
            }
            .font(.system(size: 10.5, weight: .bold, design: .rounded)).monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}

/// The black band: title and room on the left, tasks and role on the right. Plain text only, never glass.
struct HeaderBand: View {
    let controller: GameController
    var body: some View {
        let _ = controller.revision
        HStack(spacing: 10) {
            Text("SLEEPER").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(2).foregroundStyle(Theme.accent)
            if let g = controller.game, case .playing = g.phase {
                Text(g.map.roomName(at: g.me.pos.tile)).font(Theme.body(11.5)).foregroundStyle(Theme.soft)
            } else {
                Text("The Abyss").font(Theme.body(11.5)).foregroundStyle(Theme.soft)
            }
            Spacer()
            if let g = controller.game {
                if case .oxygen(let t, _) = g.sabotage {
                    Text("O₂ \(Int(t.rounded(.up)))s").font(Theme.body(11.5, .bold)).foregroundStyle(Theme.alert).monospacedDigit()
                } else if g.sabotage == .lights {
                    Text("LIGHTS OUT").font(Theme.body(11, .bold)).foregroundStyle(Theme.alert)
                }
                HStack(spacing: 6) {
                    Text("Tasks").font(Theme.body(11)).foregroundStyle(Theme.soft)
                    Capsule().fill(.white.opacity(0.12)).frame(width: 90, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.good).frame(width: 90 * g.taskProgress, height: 6)
                        }
                }
                if g.me.isTraitor {
                    Text("TRAITOR").font(Theme.body(10.5, .heavy)).foregroundStyle(Theme.alert)
                } else if !g.me.alive {
                    Text("GHOST").font(Theme.body(10.5, .heavy)).foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(.horizontal, 22)
    }
}

/// The SpriteKit view plus every overlay.
struct GameArea: View {
    let controller: GameController
    var body: some View {
        let _ = controller.revision
        ZStack {
            if !controller.snapshotMode { Theme.deep }
            SceneHost(controller: controller)
            switch controller.screen {
            case .lobby:
                LobbyView(controller: controller)
            case .game:
                if let g = controller.game {
                    GameOverlays(controller: controller, game: g)
                }
            }
            if controller.paused && controller.screen == .game {
                PausedView()
            }
        }
    }
}

/// Hosts the SKView. It never takes keyboard focus; keys reach the controller through the app's key monitor.
struct SceneHost: NSViewRepresentable {
    let controller: GameController
    func makeNSView(context: Context) -> PixelSKView {
        let v = PixelSKView()
        v.preferredFramesPerSecond = 60
        v.ignoresSiblingOrder = true
        v.allowsTransparency = false
        let scene = GameScene(size: CGSize(width: 256, height: 160))
        scene.controller = controller
        v.presentScene(scene)
        controller.skView = v
        return v
    }
    func updateNSView(_ nsView: PixelSKView, context: Context) {}
}

/// Keeps the scene at a fixed number of screen points per game pixel, so pixels stay square and crisp.
final class PixelSKView: SKView {
    static let pointsPerPixel: CGFloat = 2.5
    override var acceptsFirstResponder: Bool { false }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scene?.size = CGSize(width: max(1, (newSize.width / Self.pointsPerPixel).rounded()),
                             height: max(1, (newSize.height / Self.pointsPerPixel).rounded()))
    }
}

struct PausedView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 6) {
                Text("Paused").font(Theme.title(22)).foregroundStyle(Theme.ink)
                Text("Click the island to keep playing").font(Theme.body(12)).foregroundStyle(Theme.soft)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .panel()
        }
    }
}
