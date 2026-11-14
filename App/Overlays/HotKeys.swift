import Carbon.HIToolbox

/// Raccourcis globaux, actifs même quand Teams est au premier plan :
/// ⌃⌥1 … ⌃⌥9 → bandeau n°1 … 9 ; ⌃⌥0 → tout masquer ; ⌃⌥R → rotation (identifiant 100).
/// (API Carbon RegisterEventHotKey : aucune autorisation d'accessibilité requise.)
final class HotKeys {
    private let action: (Int) -> Void
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(action: @escaping (Int) -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue().action(Int(hotKeyID.id))
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        let keyCodes = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let bindings: [(Int, Int)] = keyCodes.enumerated().map { ($0.offset, $0.element) } + [(HotKeys.rotation, kVK_ANSI_R)]
        for (number, keyCode) in bindings {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4D61_436D), id: UInt32(number))   // 'MaCm'
            if RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | optionKey), id,
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    static let rotation = 100

    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
