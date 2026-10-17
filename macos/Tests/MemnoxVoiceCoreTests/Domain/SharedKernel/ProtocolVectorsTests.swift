import XCTest
@testable import MemnoxVoiceCore

/// Checks every signed string this app builds against the vectors memnox-runtime writes, so a change to one
/// side that the other has not made fails here rather than as a signature the daemon refuses.
final class ProtocolVectorsTests: XCTestCase {
    /// The vectors as `shared/scripts/sync-vectors.sh` copies them beside every desktop app.
    private struct Vectors: Decodable {
        let version: Int
        let messages: [Message]
        let values: [String: [String]]
    }

    private struct Message: Decodable {
        let name: String
        let inputs: [String: String?]
        let message: String
    }

    /// Five folders up from this file is macos/, and the vectors sit in shared/ beside it.
    private func vectors() throws -> Vectors {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/vectors/protocol.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    private func input(_ message: Message, _ key: String) throws -> String {
        try XCTUnwrap(message.inputs[key] ?? nil, "\(message.name) has no \(key)")
    }

    func testReadsTheVersionItWasWrittenFor() throws {
        XCTAssertEqual(try vectors().version, 1)
    }

    func testBuildsEverySignedMessageByteForByte() throws {
        for vector in try vectors().messages {
            XCTAssertEqual(try built(vector), vector.message, vector.name)
        }
    }

    func testKnowsEveryCapabilityTheRuntimeGrants() throws {
        let runtime = Set(try XCTUnwrap(vectors().values["capabilities"]))
        XCTAssertEqual(Set(Capability.allCases.map(\.rawValue)), runtime)
    }

    func testKnowsEveryWayAFollowUpReachesItsSession() throws {
        let runtime = Set(try XCTUnwrap(vectors().values["followUpOutcomes"]))
        XCTAssertEqual(Set(FollowUpOutcome.allCases.map(\.rawValue)), runtime)
    }

    /// The Swift builder for one vector; a name nobody mirrors yet fails, so a new signed message cannot go unseen.
    private func built(_ vector: Message) throws -> String? {
        switch vector.name {
        case "confirm", "confirm-proposal", "confirm-rewritten", "confirm-rewritten-empty":
            return confirmationMessage(
                subject: try input(vector, "subject"),
                answer: try input(vector, "answer"),
                edited: vector.inputs["edited"] ?? nil)
        case "pair":
            return pairingMessage(pairingId: try input(vector, "pairingId"), fingerprint: try input(vector, "fingerprint"))
        case "grant":
            let capability = try XCTUnwrap(Capability(rawValue: try input(vector, "capability")))
            return grantMessage(deviceId: try input(vector, "deviceId"), capability: capability)
        case "drive":
            return driveMessage(deviceId: try input(vector, "deviceId"), until: try input(vector, "until"))
        case "follow-up":
            return followUpMessage(sessionId: try input(vector, "sessionId"), words: try input(vector, "words"))
        case "device-proof":
            let hash = try XCTUnwrap(Data(base64Encoded: try input(vector, "handshakeHash")))
            return deviceProofMessage(handshakeHash: hash)
        default:
            XCTFail("no Swift builder mirrors the runtime's \(vector.name) message")
            return nil
        }
    }
}
