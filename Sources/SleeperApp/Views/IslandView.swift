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
        let shape = NotchPillShape(cornerRadius: NotchFloat.cornerRadius)
        let band = max(32, island.geometry.notch.height)
        ZStack {
            if controller.snapshotMode {
                // Debug snapshots composite the SpriteKit frame underneath, so leave the game area see-through.
                VStack(spacing: 0) { Color.black.frame(height: band); Color.clear }
                    .background(alignment: .bottom) { Color.black.frame(height: 8) }
                    .clipShape(shape)
            } else {
                NotchBackdrop(shape: AnyShape(shape), rendering: .material, height: island.size.height,
                              expandedHeight: island.geometry.defaultExpandedHeight, floating: true)
                    .modifier(NotchFloatShadow(on: true))
            }
            VStack(spacing: 0) {
                ZStack {
                    NotchMoveArea(driver: island)
                    HeaderBand(controller: controller)
                        .allowsHitTesting(false)
                    NotchGripDots(lit: gripHover || island.isMoving)
                        .frame(width: NotchGrip.hitSize.width, height: NotchGrip.hitSize.height)
                        .contentShape(Rectangle())
                        .onHover { gripHover = $0 }
                        .notchMoveGesture(island)
                        .notchMoveGripAccessibility(island)
                }
                .frame(height: band)
                GameArea(controller: controller)
                    .clipShape(RoundedRectangle(cornerRadius: NotchFloat.cornerRadius - 8, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                NotchResizeHandle(driver: island).frame(height: 0)
            }
            .clipShape(shape)
        }
        .frame(width: island.size.width, height: island.size.height)
        .padding(NotchFloat.margin)
        .environment(\.colorScheme, .dark)
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
    static let pointsPerPixel: CGFloat = 3
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
