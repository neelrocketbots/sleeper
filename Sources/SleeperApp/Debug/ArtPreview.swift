import AppKit
import SleeperCore

/// Debug output: writes the baked map and the character sheet as PNGs, scaled up with hard pixels.
@MainActor enum ArtPreview {
    static func write(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let map = GameMap.abyss
        try save(MapArt.compose(map), scale: 2, to: dir.appendingPathComponent("map.png"))

        let sheet = PixelCanvas(16 * 12 + 11 * 2, 18 * 4 + 6, fill: RGB(hex: 0x0B141D))
        for (i, color) in PlayerColor.allCases.enumerated() {
            let x = i * 18
            CharacterArt.draw(sheet, color: color, frame: .idle, at: x, 2)
            CharacterArt.drawHat(sheet, Hat.allCases[i % Hat.allCases.count], at: x, 0)
            CharacterArt.draw(sheet, color: color, frame: CharacterArt.Frame.allCases[2 + i % 4], at: x, 22)
        }
        for (i, hat) in Hat.allCases.enumerated() {
            CharacterArt.draw(sheet, color: .gold, frame: .idle, at: i * 18, 42)
            CharacterArt.drawHat(sheet, hat, at: i * 18, 40)
        }
        try save(sheet.image(), scale: 6, to: dir.appendingPathComponent("characters.png"))
    }

    static func save(_ img: CGImage, scale: Int, to url: URL) throws {
        let w = img.width * scale, h = img.height * scale
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
