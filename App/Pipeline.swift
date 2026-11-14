import AppKit
import AVFoundation

/// Orchestration : caméra physique → compositeur → caméra virtuelle.
/// Les réglages modifiables sont enregistrés à chaque changement.
final class Pipeline: ObservableObject {
    @Published private(set) var cameras: [AVCaptureDevice] = []
    @Published var selectedCameraID: String? {
        didSet {
            guard oldValue != selectedCameraID else { return }
            if !isAutoSelecting { preferredCameraID = selectedCameraID }
            if isRunning { start() }
        }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var sinkConnected = false
    @Published private(set) var message: String?

    // MARK: Réglages enregistrés

    @Published var autoStart: Bool {
        didSet { defaults.set(autoStart, forKey: Prefs.autoStart) }
    }

    /// Caméra choisie par l'utilisateur, conservée même si elle est momentanément absente (iPhone…).
    private var preferredCameraID: String? {
        didSet { defaults.set(preferredCameraID, forKey: Prefs.preferredCamera) }
    }
    private var isAutoSelecting = false

    // MARK: Aperçu

    @Published var previewEnabled = false {
        didSet { previewEnabled ? startPreview() : stopPreview() }
    }
    let previewSession = AVCaptureSession()

    // MARK: Chaîne vidéo

    private let defaults: UserDefaults
    private let capture = CameraCapture()
    private let compositor: Compositor
    private let sink = SinkFeeder()
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []

    init(overlays: OverlayEngine, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        compositor = Compositor(overlays: overlays)
        _autoStart = Published(initialValue: defaults.bool(forKey: Prefs.autoStart, default: false))
        preferredCameraID = defaults.string(forKey: Prefs.preferredCamera)
    }

    func bootstrap() {
        guard timer == nil else { return }

        let compositor = self.compositor, sink = self.sink
        capture.onFrame = { pixelBuffer in
            if let frame = compositor.render(camera: pixelBuffer) { sink.send(frame) }
        }

        refreshCameras()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.reconnectIfNeeded()
        }

        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshCameras()
            },
            nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshCameras()
            },
            nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                sink.disconnect()
            }
        ]

        if autoStart { start() }
    }

    // MARK: Liaison avec la caméra virtuelle

    func reconnect() {
        sink.disconnect()
        reconnectIfNeeded()
    }

    private func reconnectIfNeeded() {
        if !sink.isConnected { sink.connect() }
        let connected = sink.isConnected
        if sinkConnected != connected { sinkConnected = connected }
    }

    // MARK: Caméra physique

    func refreshCameras() {
        cameras = CameraCapture.availableCameras()
        let ids = cameras.map(\.uniqueID)

        let target: String?
        if let preferred = preferredCameraID, ids.contains(preferred) {
            target = preferred                      // la caméra préférée est (re)devenue disponible
        } else if let current = selectedCameraID, ids.contains(current) {
            target = current
        } else {
            target = ids.first
        }
        guard target != selectedCameraID else { return }
        isAutoSelecting = true
        selectedCameraID = target
        isAutoSelecting = false
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard let id = selectedCameraID, let device = cameras.first(where: { $0.uniqueID == id }) else {
            message = "Aucune caméra sélectionnée"
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.message = "Accès caméra refusé : Réglages Système › Confidentialité et sécurité › Caméra"
                    return
                }
                do {
                    try self.capture.start(device: device)
                    self.isRunning = true
                    self.message = nil
                    if self.activity == nil {   // évite l'App Nap pendant une visio
                        self.activity = ProcessInfo.processInfo.beginActivity(
                            options: [.userInitiated, .latencyCritical], reason: "Caméra virtuelle active")
                    }
                } catch {
                    self.message = "Impossible d'ouvrir \(device.localizedName) : \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        capture.stop()
        isRunning = false
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    // MARK: Aperçu de la sortie réelle (lit la caméra virtuelle comme le ferait Teams)

    private func startPreview() {
        guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video,
                                                            position: .unspecified)
                .devices.first(where: { $0.localizedName == CamConfig.deviceName }),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            message = "Caméra virtuelle introuvable : l'extension est-elle active ?"
            DispatchQueue.main.async { self.previewEnabled = false }
            return
        }
        let session = previewSession
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    private func stopPreview() {
        let session = previewSession
        DispatchQueue.global(qos: .userInitiated).async { if session.isRunning { session.stopRunning() } }
    }
}
