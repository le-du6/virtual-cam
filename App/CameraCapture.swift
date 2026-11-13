import AVFoundation

/// Capture de la caméra physique (BGRA), image par image.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum CaptureError: LocalizedError {
        case cannotAddInput, cannotAddOutput
        var errorDescription: String? {
            self == .cannotAddInput ? "entrée refusée par la session" : "sortie refusée par la session"
        }
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "macam.capture", qos: .userInteractive)

    /// Appelé sur la file de capture pour chaque image.
    var onFrame: ((CVPixelBuffer) -> Void)?

    /// Caméras physiques disponibles (notre propre caméra virtuelle exclue).
    static func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified
        ).devices.filter { $0.localizedName != CamConfig.deviceName }
    }

    func start(device: AVCaptureDevice) throws {
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration(); throw CaptureError.cannotAddInput
        }
        session.addInput(input)
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration(); throw CaptureError.cannotAddOutput
        }
        session.addOutput(output)
        session.commitConfiguration()

        queue.async { [session] in if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
