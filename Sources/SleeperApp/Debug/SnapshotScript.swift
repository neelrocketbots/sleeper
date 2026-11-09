import AppKit
import SleeperCore
import Metal
import QuartzCore
import SpriteKit

/// `Sleeper --snapshots <dir>`: plays a scripted game and saves PNGs of each screen, then quits.
/// The island is composited from the SpriteKit frame and the SwiftUI overlays, so no screen recording is needed.
@MainActor final class SnapshotScript {
    let dir: URL
    weak var panel: NSPanel?
    let controller: GameController
    private var steps: [(Double, String, () -> Void)] = []

    init(dir: URL, panel: NSPanel, controller: GameController) {
        self.dir = dir; self.panel = panel; self.controller = controller
    }

    func run() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let c = controller
        var t = 0.8
        func at(_ dt: Double, _ name: String, _ f: @escaping () -> Void = {}) { t += dt; steps.append((t, name, f)) }
        at(1.2, "01-lobby")
        at(0.2, "") { c.roleChoice = .crew; c.startGame(seed: 42) }
        at(1.0, "02-intro")
        at(4.0, "03-playing")
        at(0.2, "") { if let g = c.game { g.debugMove(0, to: TilePos(26, 6).center) } }
        at(1.2, "04-kelp-farm")
        at(0.2, "") { if let g = c.game { g.debugSabotage(.lights) } }
        at(1.2, "05-lights-out")
        func open(_ game: MiniGame) {
            c.closeMiniGame()
            guard let g = c.game, let sid = g.map.taskStations.first(where: { if case .task(_, let k) = $0.kind { return k == game }; return false })?.id else { return }
            g.debugGiveTask(sid)
            g.debugMove(0, to: g.map.station(sid).pos.center)
            c.debugOpenMiniGame(sid)
        }
        at(0.2, "") { open(.hold) }
        at(0.8, "06-minigame-hold")
        at(0.2, "") { open(.timing) }
        at(0.8, "07-minigame-timing")
        at(0.2, "") { open(.sequence) }
        at(0.6, "08-minigame-sequence")
        at(0.2, "") {
            c.closeMiniGame()
            if let g = c.game {
                let victim = g.players.first { !$0.isTraitor && !$0.isHuman }!.id
                g.debugMove(victim, to: TilePos(27, 9).center)
                g.debugKill(victim)
                g.debugMove(0, to: TilePos(26, 9).center)
            }
        }
        at(1.0, "09-body")
        at(0.2, "") { c.tabMap(true) }
        at(0.6, "10-map")
        at(0.2, "") { c.tabMap(false); c.game?.reportBody() }
        at(9.0, "11-meeting")
        at(14.0, "12-meeting-later")
        at(0.2, "") { c.game?.humanVote(.skip) }
        at(0.5, "") {}
        at(25, "13-after-meeting")
        at(0.2, "") { c.game?.debugFinish(.crew) }
        at(0.8, "14-game-over")
        at(0.5, "") { NSApp.terminate(nil) }
        for (time, name, f) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                f()
                if !name.isEmpty { self?.capture(name) }
            }
        }
    }

    private lazy var device = MTLCreateSystemDefaultDevice()
    private lazy var queue = device?.makeCommandQueue()
    private lazy var renderer: SKRenderer? = device.map { SKRenderer(device: $0) }

    /// Draws the scene into an offscreen Metal texture. Works with the display asleep.
    private func render(_ scene: SKScene, pixels: CGSize) -> CGImage? {
        guard let device, let queue, let renderer else { return nil }
        let w = Int(pixels.width), h = Int(pixels.height)
        guard w > 0, h > 0 else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc), let cb = queue.makeCommandBuffer() else { return nil }
        renderer.scene = scene
        renderer.update(atTime: CACurrentMediaTime())
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rp.colorAttachments[0].storeAction = .store
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: w, height: h), commandBuffer: cb, renderPassDescriptor: rp)
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let data = CFDataCreate(nil, bytes, bytes.count)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func capture(_ name: String) {
        guard let panel, let content = panel.contentView else { return }
        let bounds = content.bounds
        guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        content.cacheDisplay(in: bounds, to: rep)
        let scale = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) / bounds.width : 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // The SpriteKit frame first, rendered offscreen through Metal, where the SKView sits.
        if let v = controller.skView, let scene = v.scene,
           let img = render(scene, pixels: CGSize(width: v.bounds.width * scale, height: v.bounds.height * scale)) {
            let r = v.convert(v.bounds, to: content)
            if let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("raw-\(name).png"))
            }
            ctx.interpolationQuality = .none
            ctx.draw(img, in: CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale))
        }
        // Then the SwiftUI layers on top.
        if let img = rep.cgImage { ctx.interpolationQuality = .high; ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)) }
        guard let out = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
