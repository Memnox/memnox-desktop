import Carbon

/// A shortcut from anywhere, Option-Space to talk unless told otherwise. Carbon's hot key needs no Accessibility
/// permission, which a keystroke monitor would, and asking for that to open a voice is asking for too much.
final class Hotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let pressed: () -> Void
    private let number: UInt32

    /// "MNXV" as a four character code, so Carbon can tell this app's hot keys from any other.
    private static let signature: OSType = 0x4D4E_5856

    /// Talking, the first of the app's hot keys.
    static let talk = (number: UInt32(1), keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    /// Quiet, Control-Shift-M: Control and Option together are held for a rule, and Option with a letter types one.
    static let quiet = (number: UInt32(2), keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | shiftKey))

    init(_ key: (number: UInt32, keyCode: UInt32, modifiers: UInt32) = Hotkey.talk, pressed: @escaping () -> Void) {
        self.pressed = pressed
        number = key.number
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        // Every hot key the app holds reaches every handler, so each answers only to its own number.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            let hotkey = Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard read == noErr, id.signature == Hotkey.signature, id.id == hotkey.number else { return OSStatus(eventNotHandledErr) }
            hotkey.pressed()
            return noErr
        }, 1, &type, me, &handler)
        let id = EventHotKeyID(signature: Self.signature, id: key.number)
        RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &reference)
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
