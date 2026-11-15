import Carbon

// ⌥Y / ⌥N for the approval card, ⌃⌥D to mark up the screen. Carbon hotkeys need no Accessibility permission.
// Registered only while a card is up, so ⌥N still types ñ the rest of the time.
final class Hotkeys {
    private var refs: [EventHotKeyRef] = []
    private var markupRef: EventHotKeyRef?
    private let onKey: (Bool) -> Void
    private let onMarkup: () -> Void

    init(onKey: @escaping (_ allow: Bool) -> Void, onMarkup: @escaping () -> Void) {
        self.onKey = onKey
        self.onMarkup = onMarkup
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let hotkeys = Unmanaged<Hotkeys>.fromOpaque(data!).takeUnretainedValue()
            if id.id == 3 { hotkeys.onMarkup() } else { hotkeys.onKey(id.id == 1) }
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

    var markup = false {
        didSet {
            guard markup != oldValue else { return }
            if let markupRef { UnregisterEventHotKey(markupRef) }
            markupRef = nil
            guard markup else { return }
            RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x50494E47, id: 3),
                                GetApplicationEventTarget(), 0, &markupRef)
        }
    }
}
