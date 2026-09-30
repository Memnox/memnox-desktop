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

/// A daemon that answers line by line with pauses between, the way a streaming answer arrives.
final class StepLink: DaemonLink {
    let steps: [(Double, DaemonResponse)]
    var sent: [DaemonRequest] = []
    init(steps: [(Double, DaemonResponse)]) { self.steps = steps }
    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        sent.append(request)
        let steps = self.steps
        let answering = request.method == "ask"
        return AsyncThrowingStream { continuation in
            Task {
                if answering {
                    for (delay, response) in steps {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continuation.yield(response)
                    }
                }
                continuation.finish()
            }
        }
    }
}

/// A daemon that takes its time before the first word, the way a cold brain does.
final class SlowLink: DaemonLink {
    let delay: UInt64
    let answer: [DaemonResponse]
    init(seconds: Double, answer: [DaemonResponse]) {
        delay = UInt64(seconds * 1_000_000_000)
        self.answer = answer
    }
    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        let delay = self.delay
        let answer = self.answer
        return AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(nanoseconds: delay)
                for response in answer { continuation.yield(response) }
                continuation.finish()
            }
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
    var onQueue: (() -> Void)?
    func queue(_ sentence: String) {
        said.append(sentence)
        onQueue?()
        onQueue = nil
    }
    func drained() async {}
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

final class MemoryOwner: OwnerStore {
    var name: String?
    init(_ name: String?) { self.name = name }
}

func line(_ json: String) throws -> DaemonResponse { try decodeLine(json) }

func event(_ json: String) throws -> DaemonEvent {
    try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":"# + json + "}").event)
}

final class TalkingTests: XCTestCase {
    func answer() throws -> [DaemonResponse] {
        [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Two are working. "}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
        ]
    }

    func testSaysLetMeLookWhenTheAnswerIsSlowAndOnlyOnce() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0.3, answer: try answer()),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillerAfter: 0.05, fillers: ["One sec."]
        )
        await conversation.heard("what are they doing")
        XCTAssertEqual(speaker.said, ["One sec.", "Two are working."])
    }

    func testSaysNothingExtraWhenTheAnswerIsQuick() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: try answer()),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillerAfter: 0.5, fillers: ["One sec."]
        )
        await conversation.heard("what are they doing")
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(speaker.said, ["Two are working."])
    }

    func testWaitsLongerWhenSomebodyTrailsOff() {
        XCTAssertEqual(endOfSpeechPause(after: "What are my agents doing?"), 1.6)
        XCTAssertEqual(endOfSpeechPause(after: "Okay, so are you able to uh"), 2.6)
        XCTAssertEqual(endOfSpeechPause(after: "Can Claude Code connect to"), 2.6)
    }

    func testNeverSaysLetMeLookTwoTurnsRunning() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0.3, answer: try answer()),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillerAfter: 0.05, fillers: ["One sec."]
        )
        await conversation.heard("what are they doing")
        await conversation.heard("and now")
        XCTAssertEqual(speaker.said.filter { $0 == "One sec." }.count, 1)
    }

    func testSpeaksNoMarkdownAndPausesWhereADashStood() {
        XCTAssertEqual(speakable("It's stuck on `git symbolic-ref` \u{2014} **again**."), "It's stuck on git symbolic-ref, again.")
    }
}

final class OwnerTests: XCTestCase {
    func testAsksTheWayAColleagueWould() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"claude-code wants to git.push main","at":"t","agentName":"Claude","what":"push main","why":"Pushing to main needs a person.","task":"add order cancellation","place":"shop"}"#)
        XCTAssertEqual(
            heldQuestion(owner: "Moise", event: held),
            "Moise, Claude in shop, working on add order cancellation, wants to push main. Pushing to main needs a person. Allow it, or deny?"
        )
    }

    func testSaysOnlyWhatItKnows() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"codex","summary":"codex wants to rm build","at":"t","why":"deletes need a person"}"#)
        XCTAssertEqual(
            heldQuestion(owner: nil, event: held),
            "codex wants to rm build. deletes need a person. Allow it, or deny?"
        )
    }

    func testSuggestsTheFirstName() {
        XCTAssertEqual(suggestedName(fullName: "Moise Rushanika"), "Moise")
        XCTAssertEqual(suggestedName(fullName: "Cher"), "Cher")
    }

    func testRemembersTheNameInTheAppsOwnDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "memnox-owner-test-\(UUID().uuidString)"))
        let owner = DefaultsOwner(defaults: defaults)
        XCTAssertNil(owner.name)
        owner.name = "Moise"
        XCTAssertEqual(DefaultsOwner(defaults: defaults).name, "Moise")
    }
}

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
        conversation = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner("Moise"))
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

    func testQueuesNothingThatArrivesAfterAnInterruption() async throws {
        let link = StepLink(steps: [
            (0, try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"First. "}}"#)),
            (0.2, try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Second. "}}"#)),
            (0, try line(#"{"id":1,"ok":true,"chunk":{"kind":"cancelled"}}"#)),
        ])
        let conversation = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil))
        speaker.onQueue = { Task { await conversation.interrupt() } }
        await conversation.heard("tell me everything")
        XCTAssertEqual(speaker.said, ["First."])
        XCTAssertEqual(speaker.stopped, 1)
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
        XCTAssertEqual(speaker.said, ["Moise, claude-code wants to push to main. Allow it, or deny?"])
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
        await conversation.heard("yes let it push, just once")
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
        await conversation.heard("go ahead")
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"declined"}"#)]
        let proposal = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"proposal","subject":"prp_9","agent":"a","summary":"s","at":"t"}}"#).event)
        await conversation.handle(proposal)

        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.answer, "declined")
        XCTAssertNil(sent.signature)
        XCTAssertEqual(speaker.said.last, "Left as it was.")
    }

    func testTellsAHeldCallInTheBrainsOwnWordsWhenItCan() async throws {
        link.answers["brief"] = [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Moise, Claude has been on order cancellation for twenty minutes. It wants to push to main now. Should I let it? "}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
        ]
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"s","at":"t"}"#)
        await conversation.handle(held)

        let sent = try XCTUnwrap(link.sent.first)
        XCTAssertEqual(sent.method, "brief")
        XCTAssertEqual(sent.briefing, "held")
        XCTAssertEqual(sent.subject, "apr_1")
        XCTAssertEqual(sent.owner, "Moise")
        XCTAssertEqual(speaker.said.first, "Moise, Claude has been on order cancellation for twenty minutes.")
    }

    func testLeavesAnAllowNobodyAskedForAndNeverRaisesTouchID() async throws {
        let proposal = try event(#"{"kind":"proposal","subject":"prp_9","agent":"a","summary":"s","at":"t"}"#)
        await conversation.handle(proposal)
        XCTAssertEqual(key.signed, [])
        XCTAssertEqual(link.sent.last?.answer, "declined")
        XCTAssertNil(link.sent.last?.signature)
    }

    func testCatchesThemUpWhenTheyComeBack() async throws {
        link.answers["brief"] = [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Welcome back. Codex got stuck on the build and is paused."}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
        ]
        await conversation.welcomeBack(since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(link.sent.first?.briefing, "back")
        XCTAssertEqual(link.sent.first?.since, "1970-01-01T00:00:00Z")
        XCTAssertEqual(speaker.said, ["Welcome back.", "Codex got stuck on the build and is paused."])
    }

    func testSaysAnOlderDaemonCannotAnswerRatherThanWaitingForEver() async throws {
        // What 0.13 and earlier answer to any method they do not know.
        link.answers["ask"] = [try line(#"{"id":1,"ok":true}"#)]
        await conversation.heard("what is claude doing")
        XCTAssertEqual(speaker.said, [Conversation.tooOld])
    }

    func testSaysANewerDaemonsRefusalTheSameWay() async throws {
        link.answers["ask"] = [try line(#"{"id":1,"ok":false,"error":"no method ask"}"#)]
        await conversation.heard("hello")
        XCTAssertEqual(speaker.said, [Conversation.tooOld])
    }

    func testNeverCallsTheKeyRegisteredOnABareOk() async throws {
        link.answers["register-key"] = [try line(#"{"id":1,"ok":true}"#)]
        let status = await conversation.registerKey()
        XCTAssertEqual(status, .tooOld)
    }

    func testTellsADaemonThatSpeaksVoiceFromOneThatOnlySaysOk() async throws {
        link.answers["waiting"] = [try line(#"{"id":1,"ok":true}"#)]
        let old = await conversation.daemonVoice()
        XCTAssertEqual(old, .tooOld)
        link.answers["waiting"] = [try line(#"{"id":2,"ok":true,"waiting":[]}"#)]
        let ready = await conversation.daemonVoice()
        XCTAssertEqual(ready, .ready)
    }

    func testSaysSoWhenAnotherKeyIsRegistered() async throws {
        link.answers["register-key"] = [try line(#"{"id":1,"ok":false,"outcome":"another key"}"#)]
        await conversation.introduce()
        XCTAssertEqual(link.sent.first?.point, key.publicPoint)
        XCTAssertTrue(speaker.said.first?.hasPrefix("Another key is registered") ?? false)
    }
}
