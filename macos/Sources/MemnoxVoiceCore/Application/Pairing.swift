import Foundation

/// How opening a pairing went.
public enum PairingStart: Equatable, Sendable {
    /// The daemon opened one, and its QR is ready to show.
    case started(PairingInvite)
    /// The daemon said no, most often because this Mac is not connected to Memnox Cloud, and why.
    case refused(String)
    case unreachable
}

/// How the person's yes to a phone went.
public enum PairingAnswer: Equatable, Sendable {
    case paired(Device)
    /// Touch ID was cancelled, so nothing was sent and the phone still waits.
    case cancelled
    case refused(String)
    case unreachable
}

/// How a change to a paired device went.
public enum DeviceChange: Equatable, Sendable {
    case done
    /// Touch ID was cancelled, so nothing was sent.
    case cancelled
    case refused(String)
    case unreachable
}

/// Pairs a phone with this Mac and looks after the devices paired: the daemon decides and keeps them,
/// this only carries the person's answers, and every yes that widens what a phone can do is signed.
public final class Pairing {
    private let link: DaemonLink
    private let key: ConfirmKey
    /// The ids every use case shares, so no two requests in flight ever carry the same one.
    private let ids: RequestIds

    public init(link: DaemonLink, key: ConfirmKey, ids: RequestIds = RequestIds()) {
        self.link = link
        self.key = key
        self.ids = ids
    }

    /// Opens a pairing, naming this Mac to the phone when a name is given.
    public func begin(name: String? = nil) async -> PairingStart {
        var request = newRequest(.pairBegin)
        request.name = name.flatMap { $0.isEmpty ? nil : $0 }
        diary.note("opening a pairing for a phone")
        guard let response = try? await link.request(request) else {
            diary.note("the daemon did not answer pair-begin")
            return .unreachable
        }
        if response.outcomeKind == .pairing, let invite = response.pairing, invite.qr != nil {
            diary.note("pairing \(invite.id) is open until \(invite.expiresAt ?? "it runs out")")
            return .started(invite)
        }
        let why = refusal(response)
        diary.note("pairing refused: \(why)")
        return .refused(why)
    }

    /// Where the pairing stands each time it changes, ending once it is paired, declined or expired.
    public func pending(_ pairingId: String) -> AsyncThrowingStream<PairingInvite, Error> {
        var request = newRequest(.pairPending)
        request.pairingId = pairingId
        let responses = link.stream(request)
        return AsyncThrowingStream { continuation in
            let watching = Task {
                do {
                    for try await response in responses {
                        guard let invite = response.pairing else { continue }
                        diary.note("pairing \(invite.id) is \(invite.state ?? "in a state this app does not know")")
                        continuation.yield(invite)
                        if invite.pairingState?.isOver == true { break }
                    }
                    continuation.finish()
                } catch {
                    diary.note("lost the pairing \(pairingId): \(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in watching.cancel() }
        }
    }

    /// The person's yes once the digits match: Touch ID signs the pairing and the phone's key, and a cancel sends nothing.
    public func accept(_ pairingId: String, phone: PairingPhone) async -> PairingAnswer {
        let message = pairingMessage(pairingId: pairingId, fingerprint: phone.fingerprint)
        guard let signature = await signed(message, reason: "pair \(phone.name), showing \(phone.code)") else {
            diary.note("Touch ID did not sign, so \(phone.name) was not paired")
            return .cancelled
        }
        var request = newRequest(.pairAccept)
        request.pairingId = pairingId
        request.signature = signature
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.outcomeKind == .paired, let device = response.device {
            diary.note("paired \(device.name)")
            return .paired(device)
        }
        let why = refusal(response)
        diary.note("pair-accept refused: \(why)")
        return .refused(why)
    }

    /// The person's no to a phone, unsigned since saying no can do no harm.
    public func decline(_ pairingId: String) async -> DeviceChange {
        var request = newRequest(.pairDecline)
        request.pairingId = pairingId
        diary.note("declining pairing \(pairingId)")
        guard let response = try? await link.request(request) else { return .unreachable }
        return response.outcomeKind == .declined ? .done : .refused(refusal(response))
    }

    /// Every device paired with this Mac, or none when the daemon cannot say.
    public func devices() async -> [Device] {
        (try? await link.request(newRequest(.devicesList)))?.devices ?? []
    }

    /// Takes a device's access away, unsigned since it only narrows what can reach this Mac.
    public func revoke(_ device: Device) async -> DeviceChange {
        var request = newRequest(.deviceRevoke)
        request.deviceId = device.id
        diary.note("revoking \(device.name)")
        guard let response = try? await link.request(request) else { return .unreachable }
        return response.outcomeKind == .revoked ? .done : .refused(refusal(response))
    }

    /// Gives a device one more capability, which widens what it can do, so Touch ID signs it.
    public func grant(_ capability: Capability, to device: Device) async -> DeviceChange {
        let message = grantMessage(deviceId: device.id, capability: capability)
        guard let signature = await signed(message, reason: "let \(device.name) \(capability.allowing)") else {
            diary.note("Touch ID did not sign, so \(device.name) may still not \(capability.allowing)")
            return .cancelled
        }
        var request = newRequest(.deviceGrant)
        request.deviceId = device.id
        request.capability = capability.rawValue
        request.signature = signature
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.outcomeKind == .granted {
            diary.note("let \(device.name) \(capability.allowing)")
            return .done
        }
        return .refused(refusal(response))
    }

    /// Takes one capability back, unsigned since it only narrows what the device can do; taking mac also ends a live drive.
    public func ungrant(_ capability: Capability, from device: Device) async -> DeviceChange {
        var request = newRequest(.deviceUngrant)
        request.deviceId = device.id
        request.capability = capability.rawValue
        diary.note("taking \(capability.rawValue) back from \(device.name)")
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.outcomeKind == .ungranted {
            diary.note("\(device.name) can no longer \(capability.rawValue)")
            return .done
        }
        return .refused(refusal(response))
    }

    /// Tells the daemon the Kokoro voice picked, so a paired phone speaks with it; answers the voice the daemon holds.
    @discardableResult
    public func tellVoice(_ voice: String) async -> String? {
        var request = newRequest(.voiceChoice)
        request.voice = voice
        let held = (try? await link.request(request))?.voice
        diary.note("told the daemon the voice is \(voice)")
        return held
    }

    /// A signature from the person's finger, or nil when they cancelled or the key could not sign.
    private func signed(_ message: String, reason: String) async -> String? {
        do {
            return try await key.sign(message, reason: reason)
        } catch {
            diary.note("the key could not sign: \(error)")
            return nil
        }
    }

    /// The daemon's own words for a no, so the person hears why rather than a code.
    private func refusal(_ response: DaemonResponse) -> String {
        for words in [response.reason, response.error] {
            if let words, !words.isEmpty { return words }
        }
        return PairingLines.refused
    }

    private func newRequest(_ method: DaemonMethod) -> DaemonRequest {
        DaemonRequest(id: ids.next(), method: method)
    }
}

extension Capability {
    /// What it lets a device do, as words after "let iPhone", since the raw name read "gave iPhone mac".
    public var allowing: String {
        switch self {
        case .see: "see what waits on you"
        case .ask: "ask the voice"
        case .answer: "answer what waits on you"
        case .steer: "steer your sessions"
        case .rules: "change your rules"
        case .rewind: "rewind work"
        case .mac: "act on this Mac"
        }
    }
}
