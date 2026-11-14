import CoreImage
import QuartzCore

/// Anime les bandeaux affichés. Appelé à chaque image par le compositeur (file de capture),
/// piloté depuis le fil principal par OverlayStore : d'où le verrou.
final class OverlayEngine {
    static let enterDuration: CFTimeInterval = 0.8
    static let leaveDuration: CFTimeInterval = 0.5

    private enum Anchor { case left, center, right }

    private struct Slot {
        let id: UUID
        var layers: OverlayLayers
        var position: OverlayPosition
        var animation: OverlayAnimation
        var enterStart: CFTimeInterval
        var leaveStart: CFTimeInterval?
    }

    private let lock = NSLock()
    private var slots: [Slot] = []

    // MARK: Pilotage (fil principal)

    func show(id: UUID, layers: OverlayLayers, position: OverlayPosition, animation: OverlayAnimation,
              delay: CFTimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        slots.removeAll { $0.id == id }
        slots.append(Slot(id: id, layers: layers, position: position, animation: animation,
                          enterStart: CACurrentMediaTime() + delay))
    }

    /// Remplace le contenu d'un bandeau affiché sans rejouer son entrée.
    func update(id: UUID, layers: OverlayLayers, position: OverlayPosition, animation: OverlayAnimation) {
        lock.lock(); defer { lock.unlock() }
        guard let i = slots.firstIndex(where: { $0.id == id && $0.leaveStart == nil }) else { return }
        slots[i].layers = layers
        slots[i].position = position
        slots[i].animation = animation
    }

    func hide(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        let now = CACurrentMediaTime()
        for i in slots.indices where slots[i].id == id && slots[i].leaveStart == nil {
            slots[i].leaveStart = max(now, slots[i].enterStart)
        }
    }

    // MARK: Rendu (file de capture)

    func frame(at now: CFTimeInterval) -> CIImage? {
        lock.lock(); defer { lock.unlock() }
        slots.removeAll { slot in
            guard let leave = slot.leaveStart else { return false }
            return now - leave >= Self.leaveDuration
        }
        var output: CIImage?
        for slot in slots {
            let p = progress(slot, now)
            guard p > 0.001 else { continue }
            let image = Self.animated(slot.layers, position: slot.position, animation: slot.animation, progress: p)
            output = output.map { image.composited(over: $0) } ?? image
        }
        return output
    }

    /// Bandeau entièrement affiché, placé sur le canevas (aperçu de l'éditeur).
    static func placed(_ layers: OverlayLayers, at position: OverlayPosition) -> CIImage {
        animated(layers, position: position, animation: .fondu, progress: 1)
    }

    // MARK: - Animation

    private func progress(_ slot: Slot, _ now: CFTimeInterval) -> CGFloat {
        var p = easeOut(clamp((now - slot.enterStart) / Self.enterDuration))
        if let leave = slot.leaveStart {
            p = min(p, 1 - easeIn(clamp((now - leave) / Self.leaveDuration)))
        }
        return p
    }

    private static func animated(_ layers: OverlayLayers, position: OverlayPosition,
                                 animation: OverlayAnimation, progress p: CGFloat) -> CIImage {
        let fitted = fit(layers)
        let (origin, anchor) = placement(fitted.size, position)
        let w = fitted.size.width, h = fitted.size.height
        var image: CIImage

        switch animation {
        case .deroule:
            // 1) la barre d'accent se déploie, 2) le fond se déroule depuis le bord d'ancrage, 3) le texte apparaît
            let a = phase(p, 0.0, 0.35), b = phase(p, 0.15, 0.7), c = phase(p, 0.5, 1.0)
            var parts: [CIImage] = []
            if b > 0 {
                let bw = w * b
                let x: CGFloat = anchor == .right ? w - bw : (anchor == .center ? (w - bw) / 2 : 0)
                parts.append(fitted.background.cropped(to: CGRect(x: x, y: 0, width: bw, height: h)))
            }
            if let accent = fitted.accent, a > 0 {
                let ah = h * a
                parts.append(accent.cropped(to: CGRect(x: 0, y: (h - ah) / 2, width: w, height: ah)))
            }
            if c > 0 {
                let dx = (1 - c) * 20 * (anchor == .right ? 1 : -1)
                parts.append(alpha(fitted.content, c).transformed(by: CGAffineTransform(translationX: dx, y: 0)))
            }
            image = stack(parts) ?? CIImage.empty()

        case .glissement:
            image = alpha(stack([fitted.background, fitted.accent, fitted.content].compactMap { $0 })!, p)
            let travel = 1 - p
            let offset: CGAffineTransform
            switch anchor {
            case .left: offset = CGAffineTransform(translationX: -travel * (origin.x + w), y: 0)
            case .right: offset = CGAffineTransform(translationX: travel * (CGFloat(CamConfig.width) - origin.x), y: 0)
            case .center: offset = CGAffineTransform(translationX: 0, y: position.isTop
                                                     ? travel * (CGFloat(CamConfig.height) - origin.y)
                                                     : -travel * (origin.y + h))
            }
            image = image.transformed(by: offset)

        case .fondu:
            image = alpha(stack([fitted.background, fitted.accent, fitted.content].compactMap { $0 })!, p)
        }

        return image.transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    /// Réduit un bandeau trop large pour le canevas.
    private static func fit(_ layers: OverlayLayers) -> OverlayLayers {
        let maxWidth = CGFloat(CamConfig.width) - 2 * marginX
        guard layers.size.width > maxWidth else { return layers }
        let s = maxWidth / layers.size.width
        let t = CGAffineTransform(scaleX: s, y: s)
        return OverlayLayers(size: CGSize(width: layers.size.width * s, height: layers.size.height * s),
                             background: layers.background.transformed(by: t),
                             accent: layers.accent?.transformed(by: t),
                             content: layers.content.transformed(by: t))
    }

    private static let marginX: CGFloat = 56
    private static let marginBottom: CGFloat = 60
    private static let marginTop: CGFloat = 48

    private static func placement(_ size: CGSize, _ position: OverlayPosition) -> (CGPoint, Anchor) {
        let W = CGFloat(CamConfig.width), H = CGFloat(CamConfig.height)
        switch position {
        case .bottomLeft: return (CGPoint(x: marginX, y: marginBottom), .left)
        case .bottomCenter: return (CGPoint(x: ((W - size.width) / 2).rounded(), y: marginBottom), .center)
        case .topLeft: return (CGPoint(x: marginX, y: H - marginTop - size.height), .left)
        case .topRight: return (CGPoint(x: W - marginX - size.width, y: H - marginTop - size.height), .right)
        }
    }

    private static func stack(_ parts: [CIImage]) -> CIImage? {
        parts.reduce(nil) { acc, image in acc.map { image.composited(over: $0) } ?? image }
    }

    private static func alpha(_ image: CIImage, _ a: CGFloat) -> CIImage {
        a >= 0.999 ? image : image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)])
    }

    private static func phase(_ p: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
        easeOut(clamp((p - start) / (end - start)))
    }
}

private func clamp<T: BinaryFloatingPoint>(_ x: T) -> CGFloat { CGFloat(min(max(x, 0), 1)) }
private func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
private func easeIn(_ t: CGFloat) -> CGFloat { t * t * t }
