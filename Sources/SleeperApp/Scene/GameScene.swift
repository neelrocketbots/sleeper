import SleeperCore
import SpriteKit

/// Draws the game: the painted station (sea, glass tunnels, domes), props, the crew with their hats, bodies, task
/// markers, fish outside the glass, and the line-of-sight fog. Depth: z = 100 + the y (in tiles) of what stands there.
@MainActor final class GameScene: SKScene {
    static let pixel = StoryArt.unit
    weak var controller: GameController?

    private let world = SKNode()
    private let cam = SKCameraNode()
    private var actors: [Int: (node: SKNode, sprite: SKSpriteNode, hat: SKSpriteNode?, shadow: SKSpriteNode)] = [:]
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
    private var hatPlacements: [String: (center: CGPoint, size: CGSize)] = [:]

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .fill
        backgroundColor = NSColor(srgbRed: 0.03, green: 0.08, blue: 0.12, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(world)
        addChild(cam)
        camera = cam
        fog.zPosition = 1000
        cam.addChild(fog)
    }

    required init?(coder: NSCoder) { fatalError() }

    func point(_ v: Vec2) -> CGPoint { CGPoint(x: v.x * Self.pixel, y: -v.y * Self.pixel) }

    // MARK: Building

    private func build(for game: Game) {
        world.removeAllChildren()
        actors.removeAll(); bodyNodes.removeAll(); markers.removeAll()
        let map = game.map
        for piece in StationArt.pieces(map) {
            let n = SKSpriteNode(texture: piece.texture, size: piece.size)
            n.anchorPoint = CGPoint(x: 0, y: 1)
            n.position = CGPoint(x: piece.origin.x, y: -piece.origin.y)
            n.zPosition = piece.z
            world.addChild(n)
        }
        for p in map.props {
            let tex = StoryArt.prop(p.kind)
            let aspect = tex.size().height / max(1, tex.size().width)
            let footW = Double(p.rect.width) * Self.pixel, footH = Double(p.rect.height) * Self.pixel
            var w = footW * (p.kind == .table ? 1.08 : 0.98)
            // Keep tall machines from towering: at most a couple of tiles above their footprint.
            let maxH = footH + 26
            if w * aspect > maxH { w = maxH / aspect }
            let n = SKSpriteNode(texture: tex, size: CGSize(width: w, height: w * aspect))
            let cx = (Double(p.rect.x0) + Double(p.rect.width) / 2) * Self.pixel
            if StoryArt.isFlat(p.kind) {
                n.size = CGSize(width: footW, height: footH * 1.05)
                n.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                n.position = CGPoint(x: cx, y: -(Double(p.rect.y0) + Double(p.rect.height) / 2) * Self.pixel)
                n.zPosition = 3
            } else {
                n.anchorPoint = CGPoint(x: 0.5, y: 0)
                n.position = CGPoint(x: cx, y: -Double(p.rect.y1 + 1) * Self.pixel + 3)
                n.zPosition = 100 + Double(p.rect.y1 + 1) - 0.05
            }
            world.addChild(n)
        }
        for p in game.players {
            let node = SKNode()
            let sh = SKSpriteNode(texture: StoryArt.shadow, size: CGSize(width: 18, height: 6))
            sh.zPosition = -0.5
            let s = SKSpriteNode(texture: StoryArt.crew(.idle, p.color), size: StoryArt.size(.idle))
            s.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.addChild(sh)
            node.addChild(s)
            var hat: SKSpriteNode?
            if let tex = StoryArt.hat(p.hat) {
                let h = SKSpriteNode(texture: tex)
                h.zPosition = 0.1
                s.addChild(h)
                hat = h
            }
            world.addChild(node)
            actors[p.id] = (node, s, hat, sh)
        }
        for st in map.taskStations {
            let mk = SKSpriteNode(texture: StoryArt.marker, size: CGSize(width: 9, height: 12))
            mk.anchorPoint = CGPoint(x: 0.5, y: 0)
            mk.zPosition = 900
            mk.isHidden = true
            world.addChild(mk)
            markers[st.id] = mk
        }
        addFish(map)
        builtFor = ObjectIdentifier(game)
        camPos = point(game.me.pos)
    }

    /// Fish drifting through the water outside, seen through the glass.
    private func addFish(_ map: GameMap) {
        var rng = SeededRandom(seed: 7)
        for i in 0..<18 {
            let y = (2 + rng.unit() * Double(map.height - 4)) * Self.pixel
            let speed = 6 + rng.unit() * 8
            let f = SKSpriteNode(texture: StoryArt.fish(i), size: CGSize(width: 11, height: 6))
            f.zPosition = -15
            f.alpha = 0.85
            let width = Double(map.width) * Self.pixel
            let startX = rng.unit() * width
            f.position = CGPoint(x: startX, y: -y)
            let right = rng.chance(0.5)
            f.xScale = right ? 1 : -1
            world.addChild(f)
            let across = SKAction.moveTo(x: right ? width + 20 : -20, duration: (right ? width - startX : startX) / speed)
            let wrap = SKAction.moveTo(x: right ? -20 : width + 20, duration: 0)
            let full = SKAction.moveTo(x: right ? width + 20 : -20, duration: (width + 40) / speed)
            let bob = SKAction.sequence([.moveBy(x: 0, y: 3, duration: 1.4), .moveBy(x: 0, y: -3, duration: 1.4)])
            f.run(.group([.sequence([across, .repeatForever(.sequence([wrap, full]))]), .repeatForever(bob)]))
        }
    }

    private func placement(_ hat: Hat, _ pose: StoryArt.Pose) -> (center: CGPoint, size: CGSize)? {
        let key = "\(hat.rawValue)-\(pose.rawValue)"
        if let p = hatPlacements[key] { return p }
        guard let p = StoryArt.hatPlacement(hat, on: pose) else { return nil }
        hatPlacements[key] = p
        return p
    }

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

        let target = point(me.pos)
        camPos.x += (target.x - camPos.x) * min(1, dt * 10)
        camPos.y += (target.y - camPos.y) * min(1, dt * 10)
        cam.position = CGPoint(x: camPos.x.rounded(), y: camPos.y.rounded())

        for p in game.players {
            guard let a = actors[p.id] else { continue }
            let visible: Bool
            if p.id == me.id { visible = true }
            else if !p.alive { visible = ghostView }
            else { visible = ghostView || game.canSee(me, p.pos) }
            a.node.isHidden = !visible
            guard visible else { continue }
            let pose: StoryArt.Pose
            if p.moving { pose = [.idle, .walk1, .idle, .walk2][Int(p.walkPhase * 0.7) % 4] } else { pose = .idle }
            a.sprite.texture = StoryArt.crew(pose, p.color)
            a.sprite.size = StoryArt.size(pose)
            a.sprite.xScale = p.facing < 0 ? -1 : 1
            a.sprite.alpha = p.alive ? 1 : 0.45
            a.shadow.isHidden = !p.alive
            if let hat = a.hat, let pl = placement(p.hat, pose) {
                hat.position = pl.center
                hat.size = pl.size
            }
            var at = point(p.pos)
            at.y -= 4
            // A gentle bob: breathing when still, a hop when walking, floating as a ghost.
            if !p.alive { at.y += CGFloat(sin(game.time * 2 + Double(p.id)) * 2) }
            else if p.moving { at.y += CGFloat(abs(sin(p.walkPhase * 1.1)) * 1.2) }
            else { a.sprite.yScale = 1 + CGFloat(sin(game.time * 2.4 + Double(p.id)) * 0.015) }
            if p.working { at.y += CGFloat(Int(game.time * 6) % 2) }
            a.node.position = at
            a.node.zPosition = 100 + p.pos.y
        }

        let liveBodies = Set(game.bodies.map(\.victim))
        for (id, n) in bodyNodes where !liveBodies.contains(id) { n.removeFromParent(); bodyNodes[id] = nil }
        for b in game.bodies {
            let n = bodyNodes[b.victim] ?? {
                let n = SKSpriteNode(texture: StoryArt.crew(.body, game.players[b.victim].color), size: StoryArt.size(.body))
                // Lying on its side on the floor.
                n.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                n.zRotation = b.victim % 2 == 0 ? .pi / 2 : -.pi / 2
                world.addChild(n)
                bodyNodes[b.victim] = n
                return n
            }()
            n.position = point(b.pos) + CGPoint(x: 0, y: -2)
            n.zPosition = 100 + b.pos.y - 0.01
            n.isHidden = !(ghostView || game.canSee(me, b.pos))
        }

        let mine = Set(me.isTraitor ? [] : me.tasks.filter { !me.done.contains($0) })
        for (sid, mk) in markers {
            let st = game.map.station(sid)
            let on = mine.contains(sid) && (ghostView || game.canSee(me, st.pos.center))
            mk.isHidden = !on
            if on {
                let at = point(st.pos.center)
                mk.position = CGPoint(x: at.x, y: at.y + 14 + CGFloat(sin(game.time * 4) * 1.5))
            }
        }

        bubbles(game, dt: dt)
        fogTimer -= dt
        if fogTimer <= 0 { fogTimer = 1.0 / 30; updateFog(game) }
    }

    private func bubbles(_ game: Game, dt: Double) {
        bubbleTimer -= dt
        guard bubbleTimer <= 0 else { return }
        bubbleTimer = 0.4
        let me = game.me
        let at = me.pos + Vec2(Double.random(in: -5...5), Double.random(in: -3...3))
        guard game.canSee(me, at) else { return }
        let b = SKSpriteNode(texture: StoryArt.bubble, size: CGSize(width: 4, height: 4))
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
        let raise = StationArt.wallHeight / Self.pixel
        tex.modifyPixelData { ptr, _ in
            guard let p = ptr?.assumingMemoryBound(to: UInt8.self) else { return }
            for ty in 0..<h {
                for tx in 0..<w {
                    let wx = (ox + (Double(tx) + 0.5) * cell) / px
                    let wy = -(oy - (Double(h - 1 - ty) + 0.5) * cell) / px
                    var pt = Vec2(wx, wy)
                    // A dome's back wall is painted above its footprint: light it by the floor in front of it.
                    if map.blocksSight(pt.tile) {
                        let lifted = Vec2(wx, wy + raise)
                        if !map.blocksSight(lifted.tile) { pt = lifted }
                    }
                    var dark: Double
                    if ghost {
                        dark = 0.12
                    } else {
                        let d = pt.distance(to: eye)
                        if d > radius + 0.6 { dark = 0.84 }
                        else if !Sight.clear(map, from: eye, to: pt, ignoringTarget: true) { dark = 0.84 }
                        else if d <= inner { dark = 0 }
                        else { dark = min(0.84, (d - inner) / (radius + 0.6 - inner) * 0.84) }
                    }
                    let i = (ty * w + tx) * 4
                    let a = UInt8(dark * 255)
                    p[i] = UInt8(Double(a) * 0.02); p[i + 1] = UInt8(Double(a) * 0.04); p[i + 2] = UInt8(Double(a) * 0.08); p[i + 3] = a
                }
            }
        }
        let fx = (ox + Double(w) * fogCell / 2) - camX, fy = (oy - Double(h) * fogCell / 2) - camY
        fog.position = CGPoint(x: fx, y: fy)
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
}
