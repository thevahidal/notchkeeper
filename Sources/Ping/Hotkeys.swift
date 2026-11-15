import Carbon

// ⌥Y / ⌥N for the approval card. Carbon hotkeys need no Accessibility permission.
// Registered only while a card is up, so ⌥N still types ñ the rest of the time.
final class Hotkeys {
    private var refs: [EventHotKeyRef] = []
    private let onKey: (Bool) -> Void

    init(onKey: @escaping (_ allow: Bool) -> Void) {
        self.onKey = onKey
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            Unmanaged<Hotkeys>.fromOpaque(data!).takeUnretainedValue().onKey(id.id == 1)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            refs.forEach { UnregisterEventHotKey($0) }
            refs = []
            guard enabled else { return }
            for (id, key) in [(UInt32(1), kVK_ANSI_Y), (2, kVK_ANSI_N)] {
                var ref: EventHotKeyRef?
                RegisterEventHotKey(UInt32(key), UInt32(optionKey), EventHotKeyID(signature: 0x50494E47, id: id),
                                    GetApplicationEventTarget(), 0, &ref)
                if let ref { refs.append(ref) }
            }
        }
    }
}
