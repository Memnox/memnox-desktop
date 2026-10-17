import Carbon

/// Option-Space from anywhere. Carbon's hot key needs no Accessibility permission, which a
/// keystroke monitor would, and asking for that to open a voice is asking for too much.
final class Hotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let pressed: () -> Void

    /// "MNXV" as a four character code, so Carbon can tell this app's hot key from any other.
    private static let signature: OSType = 0x4D4E_5856
    /// The app registers one hot key, so it is number one.
    private static let hotKeyNumber: UInt32 = 1
    private static let keyCode = UInt32(kVK_Space)
    private static let modifiers = UInt32(optionKey)

    init(pressed: @escaping () -> Void) {
        self.pressed = pressed
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue().pressed()
            return noErr
        }, 1, &type, me, &handler)
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyNumber)
        RegisterEventHotKey(Self.keyCode, Self.modifiers, id, GetApplicationEventTarget(), 0, &reference)
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
