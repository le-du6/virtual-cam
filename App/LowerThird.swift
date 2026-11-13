import Foundation
import CoreGraphics
import CoreImage
import CoreText

/// Bandeau de test, volontairement sobre : il sert à valider la chaîne.
/// Les vrais modèles (styles, animations d'entrée/sortie) viendront ensuite.
enum LowerThird {
    static func render(name: String, title: String) -> CIImage? {
        guard let ctx = CGContext(data: nil, width: CamConfig.width, height: CamConfig.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let nameLine = line(name, font: font(.emphasizedSystem, 38), color: CGColor(gray: 1, alpha: 1))
        let titleLine = line(title, font: font(.system, 24), color: CGColor(gray: 0.82, alpha: 1))

        let accent: CGFloat = 8, padding: CGFloat = 26
        let textWidth = max(width(of: nameLine), width(of: titleLine))
        let box = CGRect(x: 56, y: 64, width: accent + padding * 2 + textWidth, height: 112)

        ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.08, blue: 0.14, alpha: 0.85))
        ctx.fill(box)
        ctx.setFillColor(CGColor(srgbRed: 0.0, green: 0.56, blue: 0.86, alpha: 1))
        ctx.fill(CGRect(x: box.minX, y: box.minY, width: accent, height: box.height))

        let textX = box.minX + accent + padding
        ctx.textPosition = CGPoint(x: textX, y: box.minY + 58)
        CTLineDraw(nameLine, ctx)
        ctx.textPosition = CGPoint(x: textX, y: box.minY + 24)
        CTLineDraw(titleLine, ctx)

        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    private static func font(_ type: CTFontUIFontType, _ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(type, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func line(_ text: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func width(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
