import AVFoundation
import CoreMediaIO

/// Pousse les images composées dans le flux « sink » de la caméra virtuelle
/// (API C CoreMediaIO : CMIOStreamCopyBufferQueue + CMSimpleQueueEnqueue).
final class SinkFeeder {
    private let lock = NSLock()
    private var deviceID: CMIODeviceID = 0
    private var streamID: CMIOStreamID = 0
    private var queue: CMSimpleQueue?

    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return queue != nil
    }

    /// Tente de se relier à la caméra virtuelle. Sans effet si déjà relié.
    @discardableResult
    func connect() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if queue != nil { return true }
        guard let device = Self.findVirtualDevice(), let stream = Self.sinkStream(of: device) else { return false }

        var unmanagedQueue: Unmanaged<CMSimpleQueue>?
        let status = CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &unmanagedQueue)
        guard status == noErr, let bufferQueue = unmanagedQueue?.takeRetainedValue() else { return false }
        guard CMIODeviceStartStream(device, stream) == noErr else { return false }

        deviceID = device
        streamID = stream
        queue = bufferQueue
        return true
    }

    func disconnect() {
        lock.lock(); defer { lock.unlock() }
        guard queue != nil else { return }
        CMIODeviceStopStream(deviceID, streamID)
        queue = nil
    }

    /// Appelé depuis la file de capture.
    func send(_ pixelBuffer: CVPixelBuffer) {
        lock.lock(); let queue = self.queue; lock.unlock()
        guard let queue, CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return }

        var format: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &format) == noErr,
              let format else { return }

        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                       formatDescription: format, sampleTiming: &timing,
                                                       sampleBufferOut: &sampleBuffer) == noErr,
              let sampleBuffer else { return }

        let element = Unmanaged.passRetained(sampleBuffer).toOpaque()
        if CMSimpleQueueEnqueue(queue, element: element) != noErr {
            Unmanaged<CMSampleBuffer>.fromOpaque(element).release()
        }
    }

    // MARK: - Recherche du périphérique et du flux sink

    private static func findVirtualDevice() -> CMIODeviceID? {
        // Passer d'abord par AVFoundation charge les caméras d'extensions dans le processus.
        let uid = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified)
            .devices.first(where: { $0.localizedName == CamConfig.deviceName })?.uniqueID

        let devices = objectList(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices)
        if let uid, let match = devices.first(where: { string($0, kCMIODevicePropertyDeviceUID) == uid }) {
            return match
        }
        return devices.first { string($0, kCMIOObjectPropertyName) == CamConfig.deviceName }
    }

    private static func sinkStream(of device: CMIODeviceID) -> CMIOStreamID? {
        let streams = objectList(device, kCMIODevicePropertyStreams)
        // Direction : 0 = sortie (notre sink), 1 = entrée (la caméra vue par Teams)
        return streams.first { uint32($0, kCMIOStreamPropertyDirection) == 0 }
            ?? (streams.count > 1 ? streams[1] : nil)
    }

    private static func address<T: BinaryInteger>(_ selector: T) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func objectList<T: BinaryInteger>(_ object: CMIOObjectID, _ selector: T) -> [CMIOObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let stride = MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / stride)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / stride))
    }

    private static func string<T: BinaryInteger>(_ object: CMIOObjectID, _ selector: T) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func uint32<T: BinaryInteger>(_ object: CMIOObjectID, _ selector: T) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size),
                                        &used, &value) == noErr else { return nil }
        return value
    }
}
