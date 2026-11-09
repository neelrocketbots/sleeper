import SleeperCore
import SpriteKit

/// Draws the game: the baked map, lights, characters, bodies, task markers and the line-of-sight fog.
/// It drives the controller's fixed-step clock from `update(_:)`.
@MainActor final class GameScene: SKScene {
    static let pixel = 16.0
    weak var controller: GameController?

    private let world = SKNode()
    private let cam = SKCameraNode()
    private var mapNode: SKSpriteNode?
    private var glows: [(node: SKSpriteNode, base: Double, flicker: Bool, phase: Double)] = []
    private var actors: [Int: (sprite: SKSpriteNode, shadow: SKSpriteNode, glow: SKSpriteNode?)] = [:]
    private var bodyNodes: [Int: SKSpriteNode] = [:]
    private var markers: [Int: SKSpriteNode] = [:]
    private let fog = SKSpriteNode()
    private var fogTexture: SKMutableTexture?
    private var fogSize = (w: 0, h: 0)
    private let fogCell = 4.0
    private var lastTime: TimeInterval?
    private var fogTimer = 0.0
    private var bubbleTimer = 0.0
    private var builtFor: ObjectIdentifier?
    private var camPos = CGPoint.zero

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .fill
        backgroundColor = NSColor(srgbRed: 0.016, green: 0.05, blue: 0.08, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(world)
        addChild(cam)
        camera = cam
        fog.zPosition = 1000
        fog.blendMode = .alpha
        cam.addChild(fog)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Building

    private func build(for game: Game) {
        world.removeAllChildren()
        actors.removeAll(); bodyNodes.removeAll(); markers.removeAll(); glows.removeAll()
        let layers = MapArt.layers(game.map)
        let m = SKSpriteNode(texture: layers.floor)
        m.anchorPoint = CGPoint(x: 0, y: 1)
        m.position = .zero
        m.zPosition = 0
        world.addChild(m)
        mapNode = m
        // Walls and props stand up from the floor and sort with the characters by their footprint's bottom edge.
        for r in layers.raised {
            let n = SKSpriteNode(texture: r.texture)
            n.anchorPoint = .zero
            n.position = CGPoint(x: r.x, y: -r.bottom)
            n.zPosition = 100 + r.depth
            world.addChild(n)
        }
        for l in layers.lights {
            // A wide spill on the floor, and a small bloom over everything.
            for (radius, alpha, z) in [(l.radius, 0.32, 5.0), (l.radius * 0.55, 0.14, 990.0)] {
                let g = SKSpriteNode(texture: CharacterArt.glow)
                g.size = CGSize(width: radius * 2, height: radius * 2)
                g.position = CGPoint(x: l.x, y: -l.y)
                g.color = l.color.ns
                g.colorBlendFactor = 1
                g.blendMode = .add
                g.alpha = alpha
                g.zPosition = z
                world.addChild(g)
                glows.append((g, alpha, l.flicker, Double(glows.count) * 1.7))
            }
        }
        for p in game.players {
            let s = SKSpriteNode(texture: CharacterArt.texture(p.color, p.hat, .idle, flip: false))
            s.anchorPoint = CGPoint(x: 0.5, y: 0)
            let sh = SKSpriteNode(texture: CharacterArt.shadow)
            sh.zPosition = 9
            world.addChild(sh)
            world.addChild(s)
            var glow: SKSpriteNode?
            if p.hat == .headlamp {
                let g = SKSpriteNode(texture: CharacterArt.glow)
                g.size = CGSize(width: 40, height: 40)
                g.color = NSColor(srgbRed: 1, green: 0.85, blue: 0.5, alpha: 1)
                g.colorBlendFactor = 1
                g.blendMode = .add
                g.alpha = 0.35
                g.zPosition = 6
                world.addChild(g)
                glow = g
            }
            actors[p.id] = (s, sh, glow)
        }
        for st in game.map.taskStations {
            let mk = SKSpriteNode(texture: CharacterArt.marker)
            mk.anchorPoint = CGPoint(x: 0.5, y: 0)
            mk.zPosition = 900
            mk.isHidden = true
            world.addChild(mk)
            markers[st.id] = mk
        }
        builtFor = ObjectIdentifier(game)
        camPos = point(game.me.pos)
    }

    func point(_ v: Vec2) -> CGPoint { CGPoint(x: v.x * Self.pixel, y: -v.y * Self.pixel) }

    // MARK: Frame

    override func update(_ currentTime: TimeInterval) {
        let dt = min(1.0 / 20, lastTime.map { currentTime - $0 } ?? 0)
        lastTime = currentTime
        // The game clock runs on the controller's own timer; the scene only draws.
        guard let controller, let game = controller.game else { return }
        if builtFor != ObjectIdentifier(game) { build(for: game) }
        sync(game, dt: dt)
    }

    private func sync(_ game: Game, dt: Double) {
        let me = game.me
        let ghostView = !me.alive
        let lightsOut = game.sabotage == .lights

        // Camera: ease toward the player, snapped to whole pixels so the art never shimmers.
        let target = point(me.pos)
        camPos.x += (target.x - camPos.x) * min(1, dt * 10)
        camPos.y += (target.y - camPos.y) * min(1, dt * 10)
        cam.position = CGPoint(x: camPos.x.rounded(), y: camPos.y.rounded())

        // Characters.
        for p in game.players {
            guard let a = actors[p.id] else { continue }
            let visible: Bool
            if p.id == me.id { visible = true }
            else if !p.alive { visible = ghostView }  // ghosts see ghosts
            else { visible = ghostView || game.canSee(me, p.pos) }
            a.sprite.isHidden = !visible
            a.shadow.isHidden = !visible || !p.alive
            a.glow?.isHidden = !visible || !p.alive
            guard visible else { continue }
            let frame: CharacterArt.Frame
            if p.moving {
                frame = [.walk1, .walk2, .walk3, .walk4][Int(p.walkPhase) % 4]
            } else {
                frame = Int(game.time * 1.6 + Double(p.id)) % 2 == 0 ? .idle : .idle2
            }
            a.sprite.texture = CharacterArt.texture(p.color, p.hat, frame, flip: p.facing < 0, ghost: !p.alive)
            var at = point(p.pos)
            at.y -= 4
            if !p.alive { at.y += CGFloat(sin(game.time * 2 + Double(p.id)) * 2) }  // ghosts bob
            if p.working { at.y += CGFloat(Int(game.time * 6) % 2) }
            a.sprite.position = CGPoint(x: at.x.rounded(), y: at.y.rounded())
            a.sprite.zPosition = 100 + p.pos.y
            a.shadow.position = CGPoint(x: at.x.rounded(), y: at.y.rounded() + 1)
            a.glow?.position = CGPoint(x: at.x + CGFloat(p.facing * 6), y: at.y + 10)
        }

        // Bodies.
        let liveBodies = Set(game.bodies.map(\.victim))
        for (id, n) in bodyNodes where !liveBodies.contains(id) { n.removeFromParent(); bodyNodes[id] = nil }
        for b in game.bodies {
            let n = bodyNodes[b.victim] ?? {
                let n = SKSpriteNode(texture: CharacterArt.bodyTexture(game.players[b.victim].color))
                n.anchorPoint = CGPoint(x: 0.5, y: 0.2)
                world.addChild(n)
                bodyNodes[b.victim] = n
                return n
            }()
            let at = point(b.pos)
            n.position = CGPoint(x: at.x.rounded(), y: at.y.rounded() - 4)
            n.zPosition = 100 + b.pos.y - 0.01
            n.isHidden = !(ghostView || game.canSee(me, b.pos))
        }

        // Task markers: your unfinished tasks, bobbing.
        let mine = Set(me.isTraitor ? [] : me.tasks.filter { !me.done.contains($0) })
        for (sid, mk) in markers {
            let st = game.map.station(sid)
            let on = mine.contains(sid) && (ghostView || game.canSee(me, st.pos.center))
            mk.isHidden = !on
            if on {
                let at = point(st.pos.center)
                mk.position = CGPoint(x: at.x.rounded(), y: (at.y + 12 + CGFloat(Int(game.time * 3) % 2)).rounded())
            }
        }

        // Lights flicker, and dim when the lights are out.
        for (i, g) in glows.enumerated() {
            var a = g.base * (lightsOut ? 0.35 : 1)
            if g.flicker { a *= 0.75 + 0.25 * sin(game.time * 7 + g.phase) * sin(game.time * 3.1 + g.phase) }
            glows[i].node.alpha = a
        }

        bubbles(game, dt: dt)
        fogTimer -= dt
        if fogTimer <= 0 { fogTimer = 1.0 / 30; updateFog(game) }
    }

    private func bubbles(_ game: Game, dt: Double) {
        bubbleTimer -= dt
        guard bubbleTimer <= 0 else { return }
        bubbleTimer = 0.35
        // A bubble drifts up from somewhere near the player, inside sight.
        let me = game.me
        let off = Vec2(Double.random(in: -5...5), Double.random(in: -3...3))
        let at = me.pos + off
        guard game.map[at.tile] == .floor, game.canSee(me, at) else { return }
        let b = SKSpriteNode(texture: CharacterArt.bubble)
        b.position = point(at)
        b.zPosition = 950
        b.alpha = 0
        world.addChild(b)
        let rise = SKAction.moveBy(x: CGFloat.random(in: -4...4), y: 26, duration: 2.2)
        b.run(.sequence([.group([rise, .sequence([.fadeAlpha(to: 0.7, duration: 0.4), .wait(forDuration: 1.2), .fadeOut(withDuration: 0.6)])]),
                         .removeFromParent()]))
    }

    // MARK: Fog

    private func updateFog(_ game: Game) {
        let w = Int((size.width / fogCell).rounded(.up)) + 2
        let h = Int((size.height / fogCell).rounded(.up)) + 2
        if fogTexture == nil || fogSize.w != w || fogSize.h != h {
            fogSize = (w, h)
            let t = SKMutableTexture(size: CGSize(width: w, height: h))
            t.filteringMode = .linear
            fogTexture = t
            fog.texture = t
            fog.size = CGSize(width: Double(w) * fogCell, height: Double(h) * fogCell)
        }
        guard let tex = fogTexture else { return }
        let me = game.me
        let ghost = !me.alive
        let radius = game.sightRadius(of: me)
        let eye = me.pos
        let map = game.map
        let camX = Double(cam.position.x), camY = Double(cam.position.y)
        let ox = camX - Double(w) * fogCell / 2, oy = camY + Double(h) * fogCell / 2
        let inner = radius * 0.62
        let cell = fogCell, px = Self.pixel
        let raise = Double(MapArt.wallHeight) / Self.pixel
        tex.modifyPixelData { ptr, _ in
            guard let p = ptr?.assumingMemoryBound(to: UInt8.self) else { return }
            for ty in 0..<h {
                for tx in 0..<w {
                    // Texture rows run bottom-up.
                    let wx = (ox + (Double(tx) + 0.5) * cell) / px
                    let wy = -(oy - (Double(h - 1 - ty) + 0.5) * cell) / px
                    var pt = Vec2(wx, wy)
                    // Raised walls are drawn up to a wall-height above their footprint: light them by the footprint.
                    if map.blocksSight(pt.tile) {
                        let lifted = Vec2(wx, wy + raise)
                        if !map.blocksSight(lifted.tile) || map[lifted.tile] == .wall { pt = lifted }
                    }
                    var dark: Double
                    if ghost {
                        dark = 0.12
                    } else {
                        let d = pt.distance(to: eye)
                        if d > radius + 0.6 { dark = 0.86 }
                        else if !Sight.clear(map, from: eye, to: pt, ignoringTarget: true) { dark = 0.86 }
                        else if d <= inner { dark = 0 }
                        else { dark = min(0.86, (d - inner) / (radius + 0.6 - inner) * 0.86) }
                    }
                    let i = (ty * w + tx) * 4
                    let a = UInt8(dark * 255)
                    // Premultiplied deep-sea navy.
                    p[i] = UInt8(Double(a) * 0.01); p[i + 1] = UInt8(Double(a) * 0.03); p[i + 2] = UInt8(Double(a) * 0.07); p[i + 3] = a
                }
            }
        }
        // Keep the fog grid fixed to world pixels so it doesn't swim as the camera moves.
        let fx = (ox + Double(w) * fogCell / 2) - camX, fy = (oy - Double(h) * fogCell / 2) - camY
        fog.position = CGPoint(x: fx, y: fy)
    }
}
