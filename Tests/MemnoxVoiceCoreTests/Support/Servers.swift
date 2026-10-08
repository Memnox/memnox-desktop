import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A server this Mac paired with, with keys of the right length and nothing secret in them.
func pairedServer(_ machineId: String = "mch_vps", name: String = "hostinger-vps", deviceId: String = "dev_mac",
                  pairedAt: Date = Date(timeIntervalSince1970: 1_000)) -> PairedMachine {
    PairedMachine(machineId: machineId, machine: name, relayURL: URL(string: "wss://relay.example.com/v1/relay")!, // A literal that always parses.
                  mailbox: Data(repeating: 7, count: RelayFraming.mailboxLength), deviceId: deviceId, relayToken: "rly_test",
                  runtimeStatic: Data(repeating: 1, count: 32), phonePrivateKey: Data(repeating: 2, count: 32), voice: nil,
                  speaks: false, pairedAt: pairedAt)
}

/// A memnox://pair link as memnox pair prints it, good until `expiresAt`.
func pairingLink(machine: String = "hostinger-vps", expiresAt: String = "2026-10-06T12:02:00.000Z") -> String {
    let json = """
    {"v":1,"machineId":"mch_vps","machine":"\(machine)","relayUrl":"wss://relay.example.com/v1/relay",\
    "mailbox":"\(Base64URL.encode(Data(repeating: 7, count: RelayFraming.mailboxLength)))","pairingToken":"rlp_test",\
    "runtimeNoiseStatic":"\(Data(repeating: 1, count: 32).base64EncodedString())",\
    "secret":"\(Data(repeating: 3, count: 32).base64EncodedString())","expiresAt":"\(expiresAt)"}
    """
    return "memnox://pair?d=\(Base64URL.encode(Data(json.utf8)))"
}

/// A presenter that writes down every act, so a test can say none was tried.
final class ActingPresenter: Presenter {
    var acts: [String] = []
    var cards: [String] = []
    var lives: [String] = []
    func open(_ host: DisplayHost?) async -> Bool { acts.append("open"); return true }
    func live(session: String, host: DisplayHost?) async { lives.append(session) }
    func focus(session: String, host: DisplayHost?) async -> Typed { acts.append("focus"); return .landed }
    func card(_ card: SummaryCard) async { cards.append(card.title) }
    func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { acts.append("type"); return .landed }
    func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { acts.append("prefill"); return .landed }
    func launch(_ command: String, in folder: String?) async -> Typed { acts.append("launch"); return .landed }
    func walk(_ walk: WalkCard) async {}
    func scan(_ agents: [AgentNode], title: String) async {}
    func trace(_ trace: TraceData, title: String) async {}
    func board(title: String) async {}
    func close(session: String, host: DisplayHost?, request: String) async -> Typed { acts.append("close"); return .landed }
    func interrupt(session: String, host: DisplayHost?, request: String) async -> Typed { acts.append("interrupt"); return .landed }
    func openFolder(_ path: String, in opener: FolderOpener) async -> Bool { acts.append("folder"); return true }
}
