import CryptoKit
import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A daemon that answers each method from a script and remembers every request it was sent.
final class ScriptedLink: DaemonLink {
    var sent: [DaemonRequest] = []
    var answers: [String: [DaemonResponse]] = [:]
    var unreachable = false

    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        sent.append(request)
        let scripted = answers[request.method] ?? []
        let unreachable = self.unreachable
        return AsyncThrowingStream { continuation in
            if unreachable {
                continuation.finish(throwing: ProtocolError.disconnected)
                return
            }
            for response in scripted { continuation.yield(response) }
            continuation.finish()
        }
    }
}

final class RecordingSpeaker: Speaker {
    var said: [String] = []
    var stopped = 0
    var onSpeak: (() -> Void)?
    func speak(_ sentence: String) async {
        said.append(sentence)
        onSpeak?()
        onSpeak = nil
        // Long enough for an interruption raised while speaking to land before the next sentence.
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    func stop() { stopped += 1 }
}

final class RecordingFace: Face {
    var shown: [(VoiceState, String)] = []
    func show(_ state: VoiceState, caption: String) { shown.append((state, caption)) }
    var states: [VoiceState] { shown.map(\.0) }
}

/// A person who either touches the sensor or cancels.
final class PersonKey: ConfirmKey {
    let inner = SoftwareConfirmKey()
    var touches = true
    var signed: [String] = []
    var publicPoint: String { inner.publicPoint }
    func sign(_ message: String, reason: String) async throws -> String? {
        signed.append(message)
        return touches ? try await inner.sign(message, reason: reason) : nil
    }
}

func line(_ json: String) throws -> DaemonResponse { try decodeLine(json) }

final class ProtocolTests: XCTestCase {
    func testEncodesOnlyTheFieldsSet() throws {
        var request = DaemonRequest(id: 3, method: .ask)
        request.said = "what is claude doing"
        let text = String(data: try encodeLine(request), encoding: .utf8)
        XCTAssertEqual(text, "{\"id\":3,\"method\":\"ask\",\"said\":\"what is claude doing\"}\n")
    }

    func testDecodesWhatTheRuntimeWrites() throws {
        let event = try line(#"{"id":0,"ok":true,"event":{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"claude-code wants to push","at":"2026-09-30T10:00:00.000Z","expiresAt":"2026-09-30T10:02:00.000Z"}}"#)
        XCTAssertEqual(event.event?.eventKind, .held)
        let chunk = try line(#"{"id":2,"ok":true,"chunk":{"kind":"done"}}"#)
        XCTAssertEqual(chunk.chunk?.endsTurn, true)
        XCTAssertThrowsError(try line("not json"))
    }

    func testReadsWhereASessionRuns() throws {
        let located = try line(#"{"id":7,"ok":true,"location":{"sessionId":"ses_1","agent":"claude-code","alive":true,"app":"iTerm","appPath":"/Applications/iTerm.app","tty":"ttys004","cwd":"/work/shop"}}"#)
        XCTAssertEqual(located.location?.appPath, "/Applications/iTerm.app")
        XCTAssertEqual(located.location?.alive, true)
    }

    func testSignsTheSameMessageTheRuntimeVerifies() {
        XCTAssertEqual(
            confirmationMessage(subject: "prp_1", answer: "confirmed"),
            "memnox-confirm:v1:prp_1:confirmed"
        )
    }

    func testSplitsLinesAcrossReads() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.push(Data("{\"a\":1}\n{\"b\"".utf8)), ["{\"a\":1}"])
        XCTAssertEqual(splitter.push(Data(":2}\n\n".utf8)), ["{\"b\":2}"])
    }

    func testTheSoftwareKeyShapesMatchTheRuntime() async throws {
        let key = SoftwareConfirmKey()
        let point = try XCTUnwrap(Data(base64Encoded: key.publicPoint))
        XCTAssertEqual(point.count, 65)
        XCTAssertEqual(point.first, 0x04)
        let signature = try await key.sign("m", reason: "r")
        let der = try XCTUnwrap(signature.flatMap { Data(base64Encoded: $0) })
        let publicKey = try P256.Signing.PublicKey(x963Representation: point)
        XCTAssertTrue(publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: der), for: Data("m".utf8)))
    }
}

final class SpeechTests: XCTestCase {
    func testSpeaksWholeSentencesAsTheyArrive() {
        var splitter = SentenceSplitter()
        XCTAssertEqual(splitter.push("Two sessions are "), [])
        XCTAssertEqual(splitter.push("open. Which one? Checkout"), ["Two sessions are open.", "Which one?"])
        XCTAssertEqual(splitter.push(" or api"), [])
        XCTAssertEqual(splitter.flush(), "Checkout or api")
    }

    func testANumberIsNotTheEndOfASentence() {
        var splitter = SentenceSplitter()
        XCTAssertEqual(splitter.push("It spent 3.5 minutes. Then"), ["It spent 3.5 minutes."])
    }

    func testTheCaptionIsCutAtAWord() {
        XCTAssertEqual(caption("short"), "short")
        XCTAssertEqual(
            caption("claude-code wants to push to main on the shop repository", limit: 30),
            "claude-code wants to push to…"
        )
    }

    func testNamesAToolTheWayAPersonReadsIt() {
        XCTAssertEqual(toolWord("mcp__memnox-operator__sessions"), "sessions")
        XCTAssertEqual(toolWord(nil), "the machine")
    }
}

final class ConversationTests: XCTestCase {
    var link: ScriptedLink!
    var speaker: RecordingSpeaker!
    var face: RecordingFace!
    var key: PersonKey!
    var conversation: Conversation!

    override func setUp() {
        link = ScriptedLink()
        speaker = RecordingSpeaker()
        face = RecordingFace()
        key = PersonKey()
        conversation = Conversation(link: link, speaker: speaker, key: key, face: face)
    }

    func testSendsTheWordsWholeAndSpeaksTheAnswerSentenceBySentence() async throws {
        link.answers["ask"] = [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__sessions"}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Two Claude sessions are open. "}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Which one do you mean"}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
        ]
        await conversation.heard("  yeah what's claude up to  ")

        XCTAssertEqual(link.sent.first?.said, "yeah what's claude up to")
        XCTAssertEqual(speaker.said, ["Two Claude sessions are open.", "Which one do you mean"])
        XCTAssertTrue(face.shown.contains { $0.0 == .thinking && $0.1 == "reading sessions" })
        XCTAssertEqual(face.states.last, .listening)
    }

    func testTalkingOverItStopsTheVoiceAndCancelsTheTurn() async throws {
        await conversation.interrupt()
        XCTAssertEqual(speaker.stopped, 1)
        XCTAssertEqual(link.sent.last?.method, "cancel")
    }

    func testSaysNothingMoreOnceInterrupted() async throws {
        link.answers["ask"] = [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"First. Second. "}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"cancelled"}}"#),
        ]
        speaker.onSpeak = { [unowned self] in Task { await self.conversation.interrupt() } }
        await conversation.heard("tell me everything")
        XCTAssertEqual(speaker.said, ["First."])
    }

    func testSaysASpentPlanRatherThanGoingQuiet() async throws {
        link.answers["ask"] = [try line(#"{"id":1,"ok":true,"chunk":{"kind":"limited","text":"usage limit"}}"#)]
        await conversation.heard("hello")
        XCTAssertEqual(speaker.said.last, "Your plan has reached its limit, so I could not finish that.")
    }

    func testSaysWhenMemnoxCannotBeReached() async {
        link.unreachable = true
        await conversation.heard("hello")
        XCTAssertEqual(speaker.said, ["I cannot reach Memnox on this Mac right now."])
    }

    func testAsksAboutAHeldCallOutLoud() async throws {
        let held = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"claude-code wants to push to main","at":"t"}}"#).event)
        await conversation.handle(held)
        XCTAssertEqual(speaker.said, ["claude-code wants to push to main. Allow it, or deny?"])
        XCTAssertEqual(face.states.last, .listening)
    }

    func testStopsAskingOnceItIsAnsweredElsewhere() async throws {
        let held = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"held","subject":"apr_1","agent":"a","summary":"s","at":"t"}}"#).event)
        let settled = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"settled","subject":"apr_1","agent":"a","summary":"no longer waiting on you","at":"t"}}"#).event)
        await conversation.handle(held)
        await conversation.handle(settled)
        XCTAssertEqual(speaker.stopped, 1)
        XCTAssertEqual(face.shown.last?.1, "answered elsewhere")
    }

    func testConfirmsAProposalOnlyWithTheFingerprintSignatureForThatProposal() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"confirmed"}"#)]
        let proposal = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"proposal","subject":"prp_9","agent":"agt_memnox-operator","summary":"deny railway deploy","at":"t"}}"#).event)
        await conversation.handle(proposal)

        XCTAssertEqual(key.signed, ["memnox-confirm:v1:prp_9:confirmed"])
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.method, "confirm")
        XCTAssertEqual(sent.answer, "confirmed")
        XCTAssertNotNil(sent.signature)
        XCTAssertTrue(face.states.contains(.needsYou))
        XCTAssertEqual(speaker.said.last, "Done.")
    }

    func testCancellingTouchIDDeclinesAndSendsNoSignature() async throws {
        key.touches = false
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"declined"}"#)]
        let proposal = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"proposal","subject":"prp_9","agent":"a","summary":"s","at":"t"}}"#).event)
        await conversation.handle(proposal)

        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.answer, "declined")
        XCTAssertNil(sent.signature)
        XCTAssertEqual(speaker.said.last, "Left as it was.")
    }

    func testSaysSoWhenAnotherKeyIsRegistered() async throws {
        link.answers["register-key"] = [try line(#"{"id":1,"ok":false,"outcome":"another key"}"#)]
        await conversation.introduce()
        XCTAssertEqual(link.sent.first?.point, key.publicPoint)
        XCTAssertTrue(speaker.said.first?.hasPrefix("Another key is registered") ?? false)
    }
}
