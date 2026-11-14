import AppKit

/// Icônes des cartes, dans l'esprit duotone :
///  1. un fichier du dossier Icônes (ex. SVG Font Awesome Duotone de votre abonnement : « flask » → flask.svg),
///     recoloré en bleu, la couche secondaire gardant son opacité de 40 % ;
///  2. sinon un symbole SF en rendu « hiérarchique » (deux opacités d'une même teinte).
enum Icons {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MaCam/Icons", isDirectory: true)
    }

    static func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// `side` : taille de rendu en pixels (on dessine ensuite plus petit pour un rendu net).
    static func image(_ name: String, side: CGFloat, color: NSColor) -> CGImage? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return fileIcon(name, side: side, color: color)
            ?? symbol(name, side: side, color: color)
            ?? (name == "flask.fill" ? symbol("testtube.2", side: side, color: color) : nil)
    }

    private static func fileIcon(_ name: String, side: CGFloat, color: NSColor) -> CGImage? {
        let candidates = [name, name + ".svg", name + ".pdf", name + ".png"].map { folder.appendingPathComponent($0) }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              var data = try? Data(contentsOf: url) else { return nil }

        if url.pathExtension.lowercased() == "svg", var svg = String(data: data, encoding: .utf8) {
            let hex = color.usingColorSpace(.sRGB).map {
                String(format: "#%02X%02X%02X", Int($0.redComponent * 255), Int($0.greenComponent * 255), Int($0.blueComponent * 255))
            } ?? "#2F6DB8"
            // Font Awesome Duotone : la couche secondaire est définie par une classe CSS → on l'explicite.
            svg = svg.replacingOccurrences(of: "class=\"fa-secondary\"", with: "class=\"fa-secondary\" opacity=\"0.4\"")
            svg = svg.replacingOccurrences(of: "currentColor", with: hex)
            if let range = svg.range(of: "<svg") { svg.replaceSubrange(range, with: "<svg fill=\"\(hex)\"") }
            data = Data(svg.utf8)
        }
        guard let image = NSImage(data: data), image.size.height > 0 else { return nil }
        let ratio = image.size.width / image.size.height
        image.size = ratio >= 1 ? CGSize(width: side, height: side / ratio) : CGSize(width: side * ratio, height: side)
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func symbol(_ name: String, side: CGFloat, color: NSColor) -> CGImage? {
        let config = NSImage.SymbolConfiguration(pointSize: side, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
