import Foundation

/// The phone that took the voice from this Mac, as the island names it until the phone gives it back.
public struct PhoneVoice: Equatable, Sendable {
    public let deviceId: String
    public let name: String

    public init(deviceId: String, name: String) {
        self.deviceId = deviceId
        self.name = name
    }

    /// The phone a notice names while it holds the voice, or nil once it gave the voice back.
    public init?(_ voiceOn: VoiceOn) {
        guard voiceOn.holding else { return nil }
        self.init(deviceId: voiceOn.deviceId, name: voiceOn.name)
    }

    /// What the island says while the phone talks, with a plain word when the phone gave no name.
    public var label: String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Talking on \(name.isEmpty ? "your phone" : name)"
    }
}
