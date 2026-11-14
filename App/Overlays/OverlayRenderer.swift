import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText

/// Calques d'un bandeau, en coordonnées locales (origine en bas à gauche).
/// Séparés pour pouvoir les animer indépendamment (déroulé).
struct OverlayLayers {
    var size: CGSize
    var background: CIImage
    var accent: CIImage?
    var content: CIImage
}

enum Palette {
    static let navy = CGColor(srgbRed: 0.055, green: 0.133, blue: 0.212, alpha: 1)      // #0E2236
    static let teal = CGColor(srgbRed: 0.180, green: 0.769, blue: 0.714, alpha: 1)      // #2EC4B6
    static let orange = CGColor(srgbRed: 0.949, green: 0.549, blue: 0.157, alpha: 1)    // #F28C28
    static let cardBlue = CGColor(srgbRed: 0.184, green: 0.427, blue: 0.722, alpha: 1)  // #2F6DB8
    static let cardText = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
    static let cardMuted = CGColor(srgbRed: 0.36, green: 0.37, blue: 0.40, alpha: 1)
    static let white = CGColor(gray: 1, alpha: 1)
}

/// Dessine les bandeaux (une fois par affichage ou modification ; l'animation ne fait que déplacer les calques).
enum OverlayRenderer {
    static func render(_ item: OverlayItem) -> OverlayLayers {
        switch item.style {
        case .sobre: sobre(item)
        case .marque: marque(item)
        case .carte: carte(item)
        }
    }

    // MARK: - Sobre (le bandeau d'origine)

    private static func sobre(_ item: OverlayItem) -> OverlayLayers {
        let name = TextLine(item.title, font: uiFont(.emphasizedSystem, 38), color: Palette.white)
        let title = TextLine(item.subtitle, font: uiFont(.system, 24), color: CGColor(gray: 0.82, alpha: 1))
        let accent: CGFloat = 8, padding: CGFloat = 26
        let textWidth = max(name.width, title.width)
        // Logo à droite, séparé du texte par un filet vertical
        let logo = Logos.image(item.logo, height: 56, white: item.logoWhite)
        let logoGap: CGFloat = 26, ruleGap: CGFloat = 22
        let logoBlock = logo.map { logoGap + 1 + ruleGap + CGFloat($0.width) } ?? 0
        let size = CGSize(width: ceil(accent + padding * 2 + textWidth + logoBlock), height: 112)

        return OverlayLayers(
            size: size,
            background: layer(size) { ctx in
                ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.08, blue: 0.14, alpha: 0.85))
                ctx.fill(CGRect(origin: .zero, size: size))
            },
            accent: layer(size) { ctx in
                ctx.setFillColor(CGColor(srgbRed: 0.0, green: 0.56, blue: 0.86, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: accent, height: size.height))
            },
            content: layer(size) { ctx in
                name.draw(ctx, x: accent + padding, baseline: 58)
                title.draw(ctx, x: accent + padding, baseline: 24)
                if let logo {
                    let ruleX = accent + padding + textWidth + logoGap
                    ctx.setFillColor(CGColor(gray: 1, alpha: 0.25))
                    ctx.fill(CGRect(x: ruleX, y: 24, width: 1, height: size.height - 48))
                    ctx.draw(logo, in: CGRect(x: ruleX + 1 + ruleGap, y: (size.height - CGFloat(logo.height)) / 2,
                                              width: CGFloat(logo.width), height: CGFloat(logo.height)))
                }
            })
    }

    // MARK: - Marqué (palette bleu nuit / turquoise / orange, deux étages)

    private static func marque(_ item: OverlayItem) -> OverlayLayers {
        let name = TextLine(item.title, font: NSFont.systemFont(ofSize: 36, weight: .bold) as CTFont, color: Palette.white)
        let title = TextLine(item.subtitle, font: NSFont.systemFont(ofSize: 22, weight: .semibold) as CTFont, color: Palette.navy)

        let accentW: CGFloat = 10, namePad: CGFloat = 24, titlePad: CGFloat = 18
        let titleBox = CGRect(x: 26, y: 0, width: ceil(title.width + titlePad * 2), height: 44)
        let logo = Logos.image(item.logo, height: 40, white: item.logoWhite)
        let logoGap: CGFloat = 26
        let logoBlock = logo.map { logoGap + CGFloat($0.width) } ?? 0
        let nameBox = CGRect(x: 0, y: titleBox.maxY, width: ceil(accentW + namePad * 2 + name.width + logoBlock), height: 70)
        let size = CGSize(width: max(nameBox.maxX, titleBox.maxX), height: nameBox.maxY)

        return OverlayLayers(
            size: size,
            background: layer(size) { ctx in
                ctx.setFillColor(Palette.navy.copy(alpha: 0.94)!)
                ctx.fill(nameBox)
                ctx.setFillColor(Palette.teal)
                ctx.fill(titleBox)
            },
            accent: layer(size) { ctx in
                ctx.setFillColor(Palette.orange)
                ctx.fill(CGRect(x: 0, y: nameBox.minY, width: accentW, height: nameBox.height))
            },
            content: layer(size) { ctx in
                name.draw(ctx, x: accentW + namePad, baseline: name.baseline(centeredIn: nameBox))
                if let logo {
                    ctx.draw(logo, in: CGRect(x: accentW + namePad + name.width + logoGap,
                                              y: nameBox.midY - CGFloat(logo.height) / 2,
                                              width: CGFloat(logo.width), height: CGFloat(logo.height)))
                }
                title.draw(ctx, x: titleBox.minX + titlePad, baseline: title.baseline(centeredIn: titleBox))
            })
    }

    // MARK: - Carte QR code (inspirée des encarts reveal.js)

    private static func carte(_ item: OverlayItem) -> OverlayLayers {
        if item.position.isTop { return carteVerticale(item) }
        let pad: CGFloat = 22, qrSide: CGFloat = 156, gap: CGFloat = 26, rightPad: CGFloat = 32
        let iconSide: CGFloat = 34, iconGap: CGFloat = 12, border: CGFloat = 3, radius: CGFloat = 18

        let titleLine = TextLine(item.title, font: NSFont.systemFont(ofSize: 32, weight: .bold) as CTFont, color: Palette.cardBlue)
        let subtitleLine = TextLine(item.subtitle, font: NSFont.systemFont(ofSize: 22) as CTFont, color: Palette.cardMuted)
        let urlLine = TextLine(urlAttributed(item))
        let icon = Icons.image(item.icon, side: iconSide * 2, color: NSColor(cgColor: Palette.cardBlue)!)

        let logo = Logos.image(item.logo, height: 30, white: item.logoWhite)
        let logoGap: CGFloat = 28

        let titleIndent = icon == nil ? 0 : iconSide + iconGap
        let titleRowWidth = titleIndent + titleLine.width + (logo.map { logoGap + CGFloat($0.width) } ?? 0)
        let textWidth = max(titleRowWidth, subtitleLine.width, urlLine.width)
        let size = CGSize(width: ceil(pad + qrSide + gap + textWidth + rightPad), height: qrSide + pad * 2)

        // Bloc de texte (3 lignes) centré verticalement
        let rows: (title: CGFloat, subtitle: CGFloat, url: CGFloat) = (42, 30, 28)
        let spacing: CGFloat = 10
        let blockTop = (size.height + rows.title + rows.subtitle + rows.url + spacing * 2) / 2
        let titleRow = CGRect(x: 0, y: blockTop - rows.title, width: 0, height: rows.title)
        let subtitleRow = CGRect(x: 0, y: titleRow.minY - spacing - rows.subtitle, width: 0, height: rows.subtitle)
        let urlRow = CGRect(x: 0, y: subtitleRow.minY - spacing - rows.url, width: 0, height: rows.url)
        let textX = pad + qrSide + gap

        return OverlayLayers(
            size: size,
            background: layer(size) { ctx in
                let card = CGRect(origin: .zero, size: size).insetBy(dx: border / 2, dy: border / 2)
                let path = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)
                ctx.addPath(path)
                ctx.setFillColor(Palette.white)
                ctx.fillPath()
                ctx.addPath(path)
                ctx.setStrokeColor(Palette.cardBlue)
                ctx.setLineWidth(border)
                ctx.strokePath()
            },
            accent: nil,
            content: layer(size) { ctx in
                if let qr = qrCode(item.url) {
                    // Agrandissement entier, sans lissage : modules nets, lisibles à l'écran
                    let modules = CGFloat(qr.width)
                    let side = floor(qrSide / modules) * modules
                    ctx.interpolationQuality = .none
                    ctx.draw(qr, in: CGRect(x: pad + (qrSide - side) / 2, y: pad + (qrSide - side) / 2,
                                            width: side, height: side))
                    ctx.interpolationQuality = .high
                }
                if let icon {
                    let ratio = CGFloat(icon.width) / CGFloat(icon.height)
                    let w = ratio >= 1 ? iconSide : iconSide * ratio
                    let h = ratio >= 1 ? iconSide / ratio : iconSide
                    ctx.draw(icon, in: CGRect(x: textX + (iconSide - w) / 2, y: titleRow.midY - h / 2, width: w, height: h))
                }
                titleLine.draw(ctx, x: textX + titleIndent, baseline: titleLine.baseline(centeredIn: titleRow))
                if let logo {   // logo aligné à droite, sur la ligne du titre
                    ctx.draw(logo, in: CGRect(x: size.width - rightPad - CGFloat(logo.width),
                                              y: titleRow.midY - CGFloat(logo.height) / 2,
                                              width: CGFloat(logo.width), height: CGFloat(logo.height)))
                }
                subtitleLine.draw(ctx, x: textX, baseline: subtitleLine.baseline(centeredIn: subtitleRow))
                urlLine.draw(ctx, x: textX, baseline: urlLine.baseline(centeredIn: urlRow))
            })
    }

    // MARK: - Carte QR code verticale (positions du haut)

    private static func carteVerticale(_ item: OverlayItem) -> OverlayLayers {
        let width: CGFloat = 300, pad: CGFloat = 22, border: CGFloat = 3, radius: CGFloat = 18
        let inner = width - pad * 2
        let iconSide: CGFloat = 32, iconGap: CGFloat = 12, qrMax: CGFloat = 210

        let icon = Icons.image(item.icon, side: iconSide * 2, color: NSColor(cgColor: Palette.cardBlue)!)
        let logo = Logos.image(item.logo, height: 26, white: item.logoWhite)

        // Ligne de tête : icône puis titre (sur plusieurs lignes si besoin), à sa droite
        let titleIndent = icon == nil ? 0 : iconSide + iconGap
        let title = TextBlock(attributed(item.title, NSFont.systemFont(ofSize: 25, weight: .bold) as CTFont,
                                         Palette.cardBlue), width: inner - titleIndent)
        let headRow = max(title.height, icon == nil ? 0 : iconSide)
        let subtitle = TextBlock(attributed(item.subtitle, NSFont.systemFont(ofSize: 17) as CTFont,
                                            Palette.cardMuted), width: inner)
        let url = TextBlock(urlAttributed(item, size: 15, wrap: true), width: inner)
        let qr = qrCode(item.url)
        let qrSide = qr.map { floor(qrMax / CGFloat($0.width)) * CGFloat($0.width) } ?? 0
        let logoRow = logo.map { CGFloat($0.height) } ?? 0

        // Empilement de haut en bas
        let gaps: (head: CGFloat, subtitle: CGFloat, qr: CGFloat, logo: CGFloat) = (8, 16, 14, logo == nil ? 0 : 14)
        let height = ceil(pad + headRow + gaps.head + subtitle.height + gaps.subtitle + qrSide + gaps.qr
                          + url.height + gaps.logo + logoRow + pad)
        let size = CGSize(width: width, height: height)

        return OverlayLayers(
            size: size,
            background: layer(size) { ctx in
                let card = CGRect(origin: .zero, size: size).insetBy(dx: border / 2, dy: border / 2)
                let path = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)
                ctx.addPath(path); ctx.setFillColor(Palette.white); ctx.fillPath()
                ctx.addPath(path); ctx.setStrokeColor(Palette.cardBlue); ctx.setLineWidth(border); ctx.strokePath()
            },
            accent: nil,
            content: layer(size) { ctx in
                var y = height - pad                       // bord supérieur de l'élément suivant
                if let icon {                              // icône calée sur la première ligne du titre
                    let ratio = CGFloat(icon.width) / CGFloat(icon.height)
                    let w = ratio >= 1 ? iconSide : iconSide * ratio
                    let h = ratio >= 1 ? iconSide / ratio : iconSide
                    let firstLineMid = y - min(title.height, 34) / 2
                    ctx.draw(icon, in: CGRect(x: pad + (iconSide - w) / 2, y: firstLineMid - h / 2, width: w, height: h))
                }
                title.draw(ctx, x: pad + titleIndent, top: y)
                y -= headRow + gaps.head
                subtitle.draw(ctx, x: pad, top: y); y -= subtitle.height + gaps.subtitle
                if let qr {
                    ctx.interpolationQuality = .none
                    ctx.draw(qr, in: CGRect(x: (width - qrSide) / 2, y: y - qrSide, width: qrSide, height: qrSide))
                    ctx.interpolationQuality = .high
                }
                y -= qrSide + gaps.qr
                url.draw(ctx, x: pad, top: y); y -= url.height + gaps.logo
                if let logo {                              // logo en pied de carte, à droite
                    ctx.draw(logo, in: CGRect(x: width - pad - CGFloat(logo.width), y: y - CGFloat(logo.height),
                                              width: CGFloat(logo.width), height: CGFloat(logo.height)))
                }
            })
    }

    /// « crypto.stelau.com/#/algo/hmac · § 4 » : domaine en sombre, chemin en bleu.
    private static func urlAttributed(_ item: OverlayItem, size: CGFloat = 21, wrap: Bool = false) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
        var display = item.url
        for prefix in ["https://", "http://"] where display.hasPrefix(prefix) { display.removeFirst(prefix.count) }
        if display.hasSuffix("/"), display.filter({ $0 == "/" }).count == 1 { display.removeLast() }

        let slash = display.firstIndex(of: "/") ?? display.endIndex
        let result = NSMutableAttributedString(attributedString: attributed(String(display[..<slash]), mono, Palette.cardText))
        result.append(attributed(String(display[slash...]), mono, Palette.cardBlue))
        if !item.urlNote.isEmpty { result.append(attributed("  ·  " + item.urlNote, mono, Palette.cardText)) }
        if wrap {   // carte verticale : coupure au caractère, l'URL n'a pas d'espaces
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byCharWrapping
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    // MARK: - Aperçu statique (éditeur)

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func preview(_ item: OverlayItem) -> CGImage? {
        let canvas = CGRect(x: 0, y: 0, width: CamConfig.width, height: CamConfig.height)
        let backdrop = CIImage(color: CIColor(red: 0.30, green: 0.34, blue: 0.40)).cropped(to: canvas)
            .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 1.2, kCIInputRadiusKey: 2.0])
        let overlay = OverlayEngine.placed(render(item), at: item.position)
        return ciContext.createCGImage(overlay.composited(over: backdrop), from: canvas)
    }

    // MARK: - Outils

    static func qrCode(_ string: String) -> CGImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }

    private static func layer(_ size: CGSize, _ draw: (CGContext) -> Void) -> CIImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return CIImage(cgImage: ctx.makeImage()!)
    }

    private static func uiFont(_ type: CTFontUIFontType, _ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(type, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }
}

// MARK: - Texte (CoreText)

private func attributed(_ text: String, _ font: CTFont, _ color: CGColor) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ])
}

/// Texte sur plusieurs lignes, coupé à la largeur donnée.
private struct TextBlock {
    let framesetter: CTFramesetter
    let width: CGFloat
    let height: CGFloat

    init(_ string: NSAttributedString, width: CGFloat) {
        framesetter = CTFramesetterCreateWithAttributedString(string)
        self.width = width
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        height = string.length == 0 ? 0 : ceil(fit.height) + 2
    }

    /// `top` : ordonnée du bord supérieur (repère CoreGraphics, origine en bas).
    func draw(_ ctx: CGContext, x: CGFloat, top: CGFloat) {
        guard height > 0 else { return }
        let path = CGPath(rect: CGRect(x: x, y: top - height, width: width, height: height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, ctx)
    }
}

private struct TextLine {
    let line: CTLine
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat

    init(_ string: NSAttributedString) {
        line = CTLineCreateWithAttributedString(string)
        var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
        width = CGFloat(CTLineGetTypographicBounds(line, &a, &d, &l))
        ascent = a
        descent = d
    }

    init(_ text: String, font: CTFont, color: CGColor) {
        self.init(attributed(text, font, color))
    }

    func baseline(centeredIn rect: CGRect) -> CGFloat {
        rect.midY - (ascent - descent) / 2
    }

    func draw(_ ctx: CGContext, x: CGFloat, baseline: CGFloat) {
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)
    }
}
