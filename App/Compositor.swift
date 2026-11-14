import CoreImage
import CoreVideo
import QuartzCore

/// Assemble l'image finale : caméra recadrée en 16:9 + bandeaux animés.
/// Point d'entrée prévu pour les futures sources ScreenCaptureKit.
final class Compositor {
    private let size = CGSize(width: CamConfig.width, height: CamConfig.height)
    private let context = CIContext(options: [.cacheIntermediates: false])   // Metal par défaut
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var pool: CVPixelBufferPool?

    private let overlays: OverlayEngine

    init(overlays: OverlayEngine) {
        self.overlays = overlays
        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey: CamConfig.width,
            kCVPixelBufferHeightKey: CamConfig.height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary   // indispensable pour passer à l'extension
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
    }

    func render(camera pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let pool else { return nil }
        let frame = CGRect(origin: .zero, size: size)

        // Remplissage 16:9 centré (aspect fill)
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(
            translationX: (size.width - image.extent.width) / 2 - image.extent.minX,
            y: (size.height - image.extent.height) / 2 - image.extent.minY))
        image = image.cropped(to: frame)

        if let overlay = overlays.frame(at: CACurrentMediaTime()) { image = overlay.composited(over: image) }

        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output) == kCVReturnSuccess,
              let output else { return nil }
        context.render(image, to: output, bounds: frame, colorSpace: colorSpace)
        return output
    }
}
