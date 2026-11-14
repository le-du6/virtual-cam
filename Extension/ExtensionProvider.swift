// Extension caméra CoreMediaIO.
//
// Un périphérique « MaCam » avec deux flux :
//  - source : lu par Teams, Zoom, FaceTime… (émis ici à cadence fixe)
//  - sink   : alimenté par l'app MaCam avec les images déjà composées
// Sans image récente de l'app, l'extension émet la mire « Stelau revient vite… » (Placeholder.swift).

import Foundation
import CoreGraphics
import CoreMedia
import CoreMediaIO
import CoreText
import CoreVideo
import IOKit.audio
import os

private let log = Logger(subsystem: "fr.stelau.macam", category: "extension")

// Identifiants fixes : les applis de visio mémorisent ainsi la caméra choisie.
private let kDeviceID = UUID(uuidString: "A3C1F0E2-7B4D-4C9A-8E61-5D2F9B7C4A01")!
private let kSourceStreamID = UUID(uuidString: "A3C1F0E2-7B4D-4C9A-8E61-5D2F9B7C4A02")!
private let kSinkStreamID = UUID(uuidString: "A3C1F0E2-7B4D-4C9A-8E61-5D2F9B7C4A03")!

/// Au-delà de ce délai sans image de l'app, on bascule sur la mire.
private let kStaleFrameNs: UInt64 = 500_000_000

private func hostTimeNs(_ time: CMTime) -> UInt64 {
    UInt64(max(0, time.seconds) * Double(NSEC_PER_SEC))
}

// MARK: - Provider

final class ProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: DeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = DeviceSource(localizedName: CamConfig.deviceName)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Impossible d'ajouter le périphérique : \(error)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { props.manufacturer = "Stelau" }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

// MARK: - Device

final class DeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var sourceStream: SourceStream!
    private var sinkStream: SinkStream!

    private let frameDuration = CMTime(value: 1, timescale: CMTimeScale(CamConfig.frameRate))
    private var placeholders: [CVPixelBuffer] = []

    // Émission vers les clients (Teams, Zoom…)
    private let timerQueue = DispatchQueue(label: "macam.output", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var sourceStarts = 0

    // Dernière image reçue de l'app via le sink
    private let lock = NSLock()
    private var lastFrame: CVPixelBuffer?
    private var lastFrameNs: UInt64 = 0
    private var sinkActive = false

    init(localizedName: String) {
        super.init()
        device = CMIOExtensionDevice(localizedName: localizedName, deviceID: kDeviceID,
                                     legacyDeviceID: nil, source: self)

        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: kCVPixelFormatType_32BGRA,
                                       width: Int32(CamConfig.width), height: Int32(CamConfig.height),
                                       extensions: nil, formatDescriptionOut: &description)
        guard let description else { fatalError("Format vidéo invalide") }
        let format = CMIOExtensionStreamFormat(formatDescription: description,
                                               maxFrameDuration: frameDuration,
                                               minFrameDuration: frameDuration,
                                               validFrameDurations: nil)

        sourceStream = SourceStream(localizedName: "MaCam.Video", streamID: kSourceStreamID,
                                    format: format, owner: self)
        sinkStream = SinkStream(localizedName: "MaCam.Sink", streamID: kSinkStreamID,
                                format: format, owner: self)
        do {
            try device.addStream(sourceStream.stream)   // l'ordre compte : source puis sink
            try device.addStream(sinkStream.stream)
        } catch {
            fatalError("Impossible d'ajouter les flux : \(error)")
        }
        placeholders = Placeholder.makeFrames()
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) { props.transportType = kIOAudioDeviceTransportTypeVirtual }
        if properties.contains(.deviceModel) { props.model = "MaCam" }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: Flux source (vers les applis de visio)

    func startSource() {
        timerQueue.async { [self] in
            sourceStarts += 1
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
            t.schedule(deadline: .now(), repeating: frameDuration.seconds, leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.emitFrame() }
            t.resume()
            timer = t
            log.info("Flux de sortie démarré")
        }
    }

    func stopSource() {
        timerQueue.async { [self] in
            sourceStarts = max(0, sourceStarts - 1)
            guard sourceStarts == 0 else { return }
            timer?.cancel()
            timer = nil
            log.info("Flux de sortie arrêté")
        }
    }

    private func emitFrame() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let nowNs = hostTimeNs(now)

        lock.lock()
        let fresh = (lastFrame != nil && nowNs &- lastFrameNs < kStaleFrameNs) ? lastFrame : nil
        lock.unlock()

        // Mire d'attente : deux images alternées toutes les 0,5 s (curseur clignotant)
        let placeholder = placeholders.isEmpty ? nil : placeholders[Int(now.seconds * 2) % placeholders.count]
        guard let pixelBuffer = fresh ?? placeholder else { return }

        var formatDescription: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                           imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &formatDescription) == noErr,
              let formatDescription else { return }

        var timing = CMSampleTimingInfo(duration: frameDuration, presentationTimeStamp: now, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: pixelBuffer,
                                                       formatDescription: formatDescription,
                                                       sampleTiming: &timing,
                                                       sampleBufferOut: &sampleBuffer) == noErr,
              let sampleBuffer else { return }

        sourceStream.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: nowNs)
    }

    // MARK: Flux sink (depuis l'app MaCam)

    func startSink(client: CMIOExtensionClient) {
        lock.lock(); sinkActive = true; lock.unlock()
        log.info("App reliée (sink démarré)")
        consume(from: client)
    }

    func stopSink() {
        lock.lock(); sinkActive = false; lastFrame = nil; lock.unlock()
        log.info("App déliée (sink arrêté)")
    }

    private func consume(from client: CMIOExtensionClient) {
        lock.lock(); let active = sinkActive; lock.unlock()
        guard active else { return }

        sinkStream.stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequenceNumber, _, _, _ in
            guard let self else { return }
            guard let sampleBuffer, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                // File vide : on réessaie un peu plus tard pour ne pas tourner à vide.
                self.timerQueue.asyncAfter(deadline: .now() + .milliseconds(5)) { self.consume(from: client) }
                return
            }
            let nowNs = hostTimeNs(CMClockGetTime(CMClockGetHostTimeClock()))
            if CVPixelBufferGetWidth(pixelBuffer) == CamConfig.width,
               CVPixelBufferGetHeight(pixelBuffer) == CamConfig.height {
                self.lock.lock()
                self.lastFrame = pixelBuffer
                self.lastFrameNs = nowNs
                self.lock.unlock()
            }
            let output = CMIOExtensionScheduledOutput(sequenceNumber: sequenceNumber, hostTimeInNanoseconds: nowNs)
            self.sinkStream.stream.notifyScheduledOutputChanged(output)
            self.consume(from: client)
        }
    }

}

// MARK: - Stream source (lu par Teams & co.)

final class SourceStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private unowned let owner: DeviceSource
    private let format: CMIOExtensionStreamFormat

    init(localizedName: String, streamID: UUID, format: CMIOExtensionStreamFormat, owner: DeviceSource) {
        self.owner = owner
        self.format = format
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID,
                                     direction: .source, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> { [.streamActiveFormatIndex, .streamFrameDuration] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { props.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { props.frameDuration = format.minFrameDuration }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws { owner.startSource() }
    func stopStream() throws { owner.stopSource() }
}

// MARK: - Stream sink (alimenté par l'app)

final class SinkStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private unowned let owner: DeviceSource
    private let format: CMIOExtensionStreamFormat
    private var client: CMIOExtensionClient?

    init(localizedName: String, streamID: UUID, format: CMIOExtensionStreamFormat, owner: DeviceSource) {
        self.owner = owner
        self.format = format
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID,
                                     direction: .sink, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration,
         .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup,
         .streamSinkBufferUnderrunCount, .streamSinkEndOfData]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { props.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { props.frameDuration = format.minFrameDuration }
        if properties.contains(.streamSinkBufferQueueSize) { props.sinkBufferQueueSize = 2 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { props.sinkBuffersRequiredForStartup = 1 }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let client else { throw NSError(domain: "MaCam", code: 1) }
        owner.startSink(client: client)
    }

    func stopStream() throws { owner.stopSink() }
}
