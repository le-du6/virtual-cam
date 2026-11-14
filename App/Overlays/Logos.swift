import AppKit

extension Notification.Name {
    /// Un logo vient d'être téléchargé : les bandeaux qui l'utilisent doivent être redessinés.
    static let logosDidChange = Notification.Name("MaCamLogosDidChange")
}

/// Logos des bandeaux. Référence = nom d'un fichier du dossier Logos (PNG, SVG, PDF…)
/// ou URL https, téléchargée une fois puis conservée dans ce même dossier.
/// Utilisé uniquement depuis le fil principal.
enum Logos {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MaCam/Logos", isDirectory: true)
    }

    static func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private static var cache: [String: CGImage] = [:]
    private static var downloading: Set<URL> = []

    /// Logo rendu à la hauteur demandée (pixels), éventuellement recoloré en blanc.
    /// Renvoie nil si la référence est vide, introuvable, ou en cours de téléchargement.
    static func image(_ reference: String, height: CGFloat, white: Bool) -> CGImage? {
        let reference = reference.trimmingCharacters(in: .whitespaces)
        guard !reference.isEmpty else { return nil }
        let key = "\(reference)|\(Int(height))|\(white)"
        if let cached = cache[key] { return cached }

        guard let file = localFile(for: reference),
              let data = try? Data(contentsOf: file),
              let image = NSImage(data: data), image.size.height > 0 else { return nil }

        let ratio = image.size.width / image.size.height
        let size = CGSize(width: ceil(height * ratio), height: ceil(height))
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(origin: .zero, size: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: rect)            // vectoriel (SVG, PDF) rendu net à la taille finale
        NSGraphicsContext.restoreGraphicsState()

        if white {                      // garde la forme (canal alpha), remplace la couleur
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(CGColor.white)
            ctx.fill(rect)
        }
        let result = ctx.makeImage()
        cache[key] = result
        return result
    }

    /// Oublie les rendus en cache (après ajout ou remplacement d'un fichier).
    static func reload() {
        cache.removeAll()
        NotificationCenter.default.post(name: .logosDidChange, object: nil)
    }

    private static func localFile(for reference: String) -> URL? {
        let fm = FileManager.default
        if let remote = URL(string: reference), let scheme = remote.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            let local = folder.appendingPathComponent("web-" + remote.lastPathComponent)
            if fm.fileExists(atPath: local.path) { return local }
            download(remote, to: local)
            return nil
        }
        return [reference, reference + ".svg", reference + ".pdf", reference + ".png"]
            .map { folder.appendingPathComponent($0) }
            .first { fm.fileExists(atPath: $0.path) }
    }

    private static func download(_ remote: URL, to local: URL) {
        guard !downloading.contains(remote) else { return }
        downloading.insert(remote)
        URLSession.shared.dataTask(with: remote) { data, response, _ in
            DispatchQueue.main.async {
                downloading.remove(remote)
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                guard (try? data.write(to: local)) != nil else { return }
                NotificationCenter.default.post(name: .logosDidChange, object: nil)
            }
        }.resume()
    }
}
