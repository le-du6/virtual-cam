// Mire d'attente « Stelau revient vite… », affichée quand l'app MaCam n'envoie pas d'images.
// Deux images pré-calculées (curseur allumé / éteint) : l'extension les alterne toutes les 0,5 s.

import CoreGraphics
import CoreText
import CoreVideo
import CryptoKit
import Foundation

enum Placeholder {
    static func makeFrames() -> [CVPixelBuffer] {
        [render(cursor: true), render(cursor: false)].compactMap { $0 }
    }

    // MARK: - Palette

    private static let navyTop = CGColor(srgbRed: 0.063, green: 0.149, blue: 0.231, alpha: 1)    // #10263B
    private static let navyBottom = CGColor(srgbRed: 0.031, green: 0.075, blue: 0.122, alpha: 1) // #08131F
    private static let teal = CGColor(srgbRed: 0.180, green: 0.769, blue: 0.714, alpha: 1)       // #2EC4B6
    private static let orange = CGColor(srgbRed: 0.949, green: 0.549, blue: 0.157, alpha: 1)     // #F28C28

    private static func white(_ a: CGFloat) -> CGColor { CGColor(gray: 1, alpha: a) }
    private static func teal(_ a: CGFloat) -> CGColor { teal.copy(alpha: a)! }

    // MARK: - Rendu

    private static func render(cursor: Bool) -> CVPixelBuffer? {
        let W = CGFloat(CamConfig.width), H = CGFloat(CamConfig.height)
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, CamConfig.width, CamConfig.height,
                                  kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: CamConfig.width, height: CamConfig.height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return pb }

        // 1. Fond bleu nuit
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let gradient = CGGradient(colorsSpace: space, colors: [navyTop, navyBottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: .zero, options: [])

        // 2. Vidage hexadécimal en filigrane, quelques octets « chauds »
        hexRain(ctx, width: W, height: H)

        // 3. Vignette : le centre reste lisible
        let vignette = CGGradient(colorsSpace: space,
                                  colors: [navyBottom.copy(alpha: 0.92)!, navyBottom.copy(alpha: 0.55)!,
                                           navyBottom.copy(alpha: 0)!] as CFArray,
                                  locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: W / 2, y: H / 2 - 10), startRadius: 0,
                               endCenter: CGPoint(x: W / 2, y: H / 2 - 10), endRadius: 520, options: [])

        // 4. Terminal en haut à gauche
        terminal(ctx, origin: CGPoint(x: 56, y: H - 56 - 152))

        // 5. Message central
        let title = Line("Stelau revient vite…", font: uiFont(.emphasizedSystem, 66), color: white(1))
        title.draw(ctx, x: (W - title.width) / 2, baseline: 382)

        ctx.setFillColor(orange)
        ctx.fill(CGRect(x: W / 2 - 60, y: 352, width: 120, height: 4))

        let prompt = Line("> En attente de démarrage de la MaCam", font: mono(26), color: teal)
        let promptX = (W - prompt.width) / 2
        prompt.draw(ctx, x: promptX, baseline: 296)
        if cursor {
            ctx.setFillColor(teal)
            ctx.fill(CGRect(x: promptX + prompt.width + 6, y: 290, width: 15, height: 28))
        }

        // 6. Pied de page : empreinte SHA-256 (réelle) et signature
        let digest = SHA256.hash(data: Data("Stelau revient vite · MaCam".utf8))
        let fingerprint = digest.prefix(12).map { String(format: "%02x", $0) }.joined(separator: ":")
        Line("SHA-256  \(fingerprint):…", font: mono(14), color: white(0.42)).draw(ctx, x: 56, baseline: 46)

        let signature = Line("Benoit LEGER-DERVILLE · Stelau · iDAKTO", font: uiFont(.system, 16), color: white(0.55))
        signature.draw(ctx, x: W - 56 - signature.width, baseline: 46)
        return pb
    }

    private static func hexRain(_ ctx: CGContext, width W: CGFloat, height H: CGFloat) {
        let font = mono(13)
        let cell = Line("00 ", font: font, color: white(0)).width
        let columns = Int(W / cell) + 1
        var rng = LCG(seed: 0x5354_454C_4155)   // « STELAU »
        var y: CGFloat = H - 14
        while y > 0 {
            var row = ""
            var hot: [(Int, String)] = []
            for c in 0..<columns {
                let value = UInt8(truncatingIfNeeded: rng.next())
                let byte = (value < 16 ? "0" : "") + String(value, radix: 16)
                row += byte + " "
                if rng.next() % 31 == 0 { hot.append((c, byte)) }
            }
            Line(row, font: font, color: teal(0.07)).draw(ctx, x: 4, baseline: y)
            for (c, byte) in hot {
                Line(byte, font: font, color: teal(0.30)).draw(ctx, x: 4 + CGFloat(c) * cell, baseline: y)
            }
            y -= 19
        }
    }

    private static func terminal(_ ctx: CGContext, origin: CGPoint) {
        let panel = CGRect(origin: origin, size: CGSize(width: 600, height: 152))
        let path = CGPath(roundedRect: panel, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 0.45)); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(teal(0.35)); ctx.setLineWidth(1); ctx.strokePath()

        let font = mono(15)
        let rows: [(tag: String?, ok: Bool, text: String)] = [
            (nil, true, "$ macam status --verbose"),
            ("OK", true, "cmio.extension   fr.stelau.macam.extension"),
            ("OK", true, "stream.source    1280×720 @ 30 fps · BGRA"),
            ("..", false, "stream.sink      en attente de l'application hôte"),
            ("..", false, "tls.handshake    ECDHE-P256 · AES-256-GCM"),
        ]
        var baseline = panel.maxY - 30
        for row in rows {
            var x = panel.minX + 18
            if let tag = row.tag {
                let open = Line("[ ", font: font, color: white(0.55))
                open.draw(ctx, x: x, baseline: baseline); x += open.width
                let status = Line(tag, font: font, color: row.ok ? teal : orange)
                status.draw(ctx, x: x, baseline: baseline); x += status.width
                let close = Line(" ] ", font: font, color: white(0.55))
                close.draw(ctx, x: x, baseline: baseline); x += close.width
            }
            Line(row.text, font: font, color: white(row.tag == nil ? 0.9 : 0.72)).draw(ctx, x: x, baseline: baseline)
            baseline -= 25
        }
    }

    // MARK: - Outils

    private static func uiFont(_ type: CTFontUIFontType, _ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(type, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func mono(_ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil) ?? CTFontCreateWithName("Menlo" as CFString, size, nil)
    }

    private struct Line {
        let line: CTLine
        let width: CGFloat

        init(_ text: String, font: CTFont, color: CGColor) {
            let string = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ])
            line = CTLineCreateWithAttributedString(string)
            width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }

        func draw(_ ctx: CGContext, x: CGFloat, baseline: CGFloat) {
            ctx.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, ctx)
        }
    }

    /// Générateur pseudo-aléatoire déterministe : la mire est identique à chaque lancement.
    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
    }
}
