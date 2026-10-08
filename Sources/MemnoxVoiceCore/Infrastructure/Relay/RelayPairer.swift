import Foundation

/// The pairing ceremony as remote-contract.md lays it out: XXpsk0 with the QR's secret, the runtime's
/// static key checked against the QR, the phone's name and signing point, the Face ID proof, and the
/// one line that says whether the person said yes on the Mac.
/// Unchecked because the key is only ever used from the one pairing task.
public struct RelayPairer: Pairer, @unchecked Sendable {
    private let dialer: RelayDialer
    private let key: ConfirmKey
    private let now: @Sendable () -> Date
    private let verdictWait: TimeInterval
    private let kind: String?

    /// Long enough for the person to walk to the Mac, read the digits and touch the sensor.
    public static let defaultVerdictWait: TimeInterval = 5 * 60
    /// What the Face ID sheet says while the proof is signed.
    static let proofReason = "Pair this iPhone with your Mac"

    public init(dialer: RelayDialer, key: ConfirmKey, now: @escaping @Sendable () -> Date = { Date.now },
                verdictWait: TimeInterval = RelayPairer.defaultVerdictWait, kind: String? = nil) {
        self.dialer = dialer
        self.key = key
        self.now = now
        self.verdictWait = verdictWait
        self.kind = kind
    }

    public func pair(_ invitation: PairingInvitation, name: String, code: @escaping @Sendable (String) -> Void) async throws -> PairedMachine {
        let socket: RelaySocket
        do {
            socket = try await dialer.dial(invitation.relayURL, token: invitation.pairingToken)
        } catch {
            throw PairingFailure.broken("the relay refused the pairing token: \(error)")
        }
        let mailbox = invitation.mailbox
        do {
            let phone = try NoiseKeypair.generate()
            let handshake = try NoiseHandshake.initiator(.xxpsk0, localPrivate: phone.privateKey, psk: invitation.secret)
            // Message 1 carries nothing; the PSK already binds it to this QR.
            try await sendHandshake(handshake.writeMessage(Data()), on: socket, mailbox: mailbox)
            let hello = try handshake.readMessage(await receiveHandshake(on: socket, mailbox: mailbox))
            guard let runtime = try handshake.remoteStatic(), runtime == invitation.runtimeStatic else {
                diary.note("pairing stopped: the runtime's static key is not the one in the QR")
                try? await sendClose(on: socket, mailbox: mailbox)
                socket.close()
                throw PairingFailure.wrongMac
            }
            let machine = (try? JSONDecoder().decode(RuntimeHello.self, from: hello))?.machine ?? invitation.machine
            let introduction = PhoneIntroduction(name: name, signingPoint: key.publicPoint, kind: kind)
            try await sendHandshake(handshake.writeMessage(JSONEncoder().encode(introduction)), on: socket, mailbox: mailbox)
            guard handshake.isFinished else { throw PairingFailure.broken("the pairing handshake did not finish in three messages") }
            let hash = try handshake.handshakeHash()
            code(try pairingCode(handshakeHash: hash))
            let tunnel = NoiseTunnel(socket: socket, mailbox: mailbox, transport: try handshake.intoTransport())
            guard let proof = try await key.sign(deviceProofMessage(handshakeHash: hash), reason: Self.proofReason) else {
                await tunnel.close()
                throw PairingFailure.cancelled
            }
            try await tunnel.send(line: JSONEncoder().encode(DeviceProof(proof: proof)))
            let verdict = try await awaitVerdict(on: tunnel)
            await tunnel.close()
            guard verdict.paired, let deviceId = verdict.deviceId, let relayToken = verdict.relayToken else {
                throw PairingFailure.declined
            }
            diary.note("paired with \(machine) as device \(deviceId)")
            return PairedMachine(machineId: invitation.machineId, machine: machine, relayURL: invitation.relayURL, mailbox: mailbox,
                             deviceId: deviceId, relayToken: relayToken, runtimeStatic: runtime, phonePrivateKey: phone.privateKey,
                             voice: verdict.voice, speaks: verdict.speaks, pairedAt: now())
        } catch let failure as PairingFailure {
            socket.close()
            throw failure
        } catch {
            socket.close()
            throw PairingFailure.broken("\(error)")
        }
    }

    /// The runtime's one line once the person decides, or a failure when it never comes.
    private func awaitVerdict(on tunnel: NoiseTunnel) async throws -> PairingVerdict {
        let wait = verdictWait
        return try await withThrowingTaskGroup(of: PairingVerdict.self) { group in
            group.addTask {
                while true {
                    let line = try await tunnel.receiveLine()
                    if let verdict = try? JSONDecoder().decode(PairingVerdict.self, from: line) { return verdict }
                    diary.note("skipped a pairing line that was not a verdict")
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(wait * Double(nanosecondsPerSecond)))
                // Closing ends the reader's blocking receive, so the group can finish.
                await tunnel.close()
                throw PairingFailure.broken("the Mac did not answer the pairing in time")
            }
            defer { group.cancelAll() }
            guard let verdict = try await group.next() else { throw PairingFailure.broken("no verdict") }
            return verdict
        }
    }
}

private func sendClose(on socket: RelaySocket, mailbox: Data) async throws {
    try await socket.send(RelayFraming.message(mailbox: mailbox, frame: Frame(kind: .close, body: Data())))
}

private let nanosecondsPerSecond: UInt64 = 1_000_000_000
