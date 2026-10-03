import CryptoKit
import Foundation
import XCTest

@testable import MemnoxVoiceCore

// Fakes for the ports, so every test runs with no socket, no audio and no Secure Enclave.

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
final class RecordingChimes: Chimes {
    var played: [Cue] = []
    func play(_ cue: Cue) { played.append(cue) }
}

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

/// Held calls, proposals and Touch ID: what is asked, signed and sent.
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
        conversation = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner("Moise"), fillers: ["One sec."])
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
        // The tool call says it is looking straight away, then the answer follows sentence by sentence.
        XCTAssertEqual(speaker.said, ["One sec.", "Two Claude sessions are open.", "Which one do you mean"])
        XCTAssertTrue(face.shown.contains { $0.0 == .thinking && $0.1 == "reading sessions" })
        XCTAssertEqual(face.states.last, .listening)
    }

    func testMarksTheWordsWholeWhenNothingMoreCameAfterAHold() async throws {
        link.answers["ask"] = [try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#)]
        await conversation.heard("open it and show me the session in", finished: true)
        XCTAssertEqual(link.sent.first?.finished, true)
        await conversation.heard("what is claude doing")
        XCTAssertNil(link.sent.last?.finished)
    }

    func testTalkingOverItStopsTheVoiceAndCancelsTheTurn() async throws {
        await conversation.interrupt()
        XCTAssertEqual(speaker.stopped, 1)
        XCTAssertEqual(link.sent.last?.method, "cancel")
    }

    func testQueuesNothingThatArrivesAfterAnInterruption() async throws {
        let link = StepLink(steps: [
            (0, try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"The first thing to say. "}}"#)),
            (0.2, try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"The second thing to say. "}}"#)),
            (0, try line(#"{"id":1,"ok":true,"chunk":{"kind":"cancelled"}}"#)),
        ])
        let conversation = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil))
        speaker.onQueue = { Task { await conversation.interrupt() } }
        await conversation.heard("tell me everything")
        XCTAssertEqual(speaker.said, ["The first thing to say."])
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
        XCTAssertEqual(speaker.said, ["My apologies, I cannot reach Memnox on this Mac at the moment."])
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
        XCTAssertEqual(speaker.said.last, "Very well. It is done.")
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
        XCTAssertEqual(speaker.said.last, "Very well. I have left it as it was.")
    }

    func testAllowsAHeldCallFromAButtonOnlyWithTheFingerprintForThatCall() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"once"}"#)]
        let outcome = await conversation.answerHeld("apr_4", .once, reason: "push to main")

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:apr_4:once"])
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.method, "confirm")
        XCTAssertEqual(sent.subject, "apr_4")
        XCTAssertEqual(sent.answer, "once")
        XCTAssertNotNil(sent.signature)
        XCTAssertEqual(speaker.said, [])
    }

    func testDeniesAHeldCallFromAButtonWithNoTouchID() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"deny"}"#)]
        let outcome = await conversation.answerHeld("apr_4", .deny, reason: "push to main")

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, [])
        XCTAssertNil(try XCTUnwrap(link.sent.last).signature)
        XCTAssertFalse(face.states.contains(.needsYou))
    }

    func testSendsNothingWhenTouchIDIsCancelledOnAHeldCall() async throws {
        key.touches = false
        let outcome = await conversation.answerHeld("apr_4", .session, reason: "push to main")

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testStopsAskingOutLoudOnceAButtonAnsweredTheCall() async throws {
        await conversation.handle(try event(#"{"kind":"held","subject":"apr_4","agent":"a","summary":"s","at":"t"}"#))
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"deny"}"#)]
        let stoppedBefore = speaker.stopped
        _ = await conversation.answerHeld("apr_4", .deny, reason: "s")

        XCTAssertEqual(speaker.stopped, stoppedBefore + 1)
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

    func testChimesAtEachMomentThePersonShouldNoticeWithoutLooking() async throws {
        let chimes = RecordingChimes()
        let conversation = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner("Moise"), chimes: chimes)
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"confirmed"}"#)]
        await conversation.heard("let it push")
        await conversation.handle(try event(#"{"kind":"held","subject":"apr_1","agent":"a","summary":"s","at":"t"}"#))
        await conversation.handle(try event(#"{"kind":"settled","subject":"apr_1","agent":"a","summary":"s","at":"t"}"#))
        await conversation.handle(try event(#"{"kind":"proposal","subject":"prp_9","agent":"a","summary":"s","at":"t"}"#))
        XCTAssertEqual(chimes.played, [.sent, .held, .settled, .allowed])
    }

    func testChimesAFailureBeforeSayingMemnoxCannotBeReached() async {
        let chimes = RecordingChimes()
        let conversation = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil), chimes: chimes)
        link.unreachable = true
        await conversation.heard("hello")
        XCTAssertEqual(chimes.played, [.sent, .failed])
    }

    func testChimesNothingForItsNameAlone() async {
        let chimes = RecordingChimes()
        let conversation = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil), chimes: chimes)
        await conversation.heard("Memnox")
        XCTAssertEqual(chimes.played, [])
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
        let spoke = await conversation.welcomeBack(since: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(spoke)
        XCTAssertEqual(link.sent.first?.briefing, "back")
        XCTAssertEqual(link.sent.first?.since, "1970-01-01T00:00:00Z")
        // A greeting that short runs on into what follows it rather than being said alone.
        XCTAssertEqual(speaker.said, ["Welcome back. Codex got stuck on the build and is paused."])
    }

    func testStaysQuietWhenTheyComeBackAndNothingWaitsOnThem() async throws {
        link.answers["brief"] = [try line(#"{"id":1,"ok":false,"error":"nothing to brief about"}"#)]
        let spoke = await conversation.welcomeBack(since: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(spoke)
        XCTAssertEqual(speaker.said, [])
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

/// A turn end to end: what is heard, what is sent, and what is said back.
final class TalkingTests: XCTestCase {
    func answer() throws -> [DaemonResponse] {
        [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Two are working. "}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
        ]
    }

    func testSaysNothingBeforeAnAnswerThatLooksNothingUpHoweverSlow() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0.3, answer: try answer()),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["One sec."]
        )
        await conversation.heard("oh that's cool")
        XCTAssertEqual(speaker.said, ["Two are working."])
    }

    func testSaysNothingAndWaitsForTheRestWhenTheyStoppedMidThought() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__keep_listening"}}"#),
                // The brain writing on after keep_listening anyway, which must not be said over them.
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"I'm listening for what you want to say about it."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["One sec."]
        )
        await conversation.heard("OK so I was working on the feature")
        XCTAssertEqual(speaker.said, [])
        XCTAssertTrue(conversation.takeHold())
        XCTAssertFalse(conversation.takeHold())
        XCTAssertFalse(conversation.takeEnd())
    }

    func testAnswersItsNameAloneWithoutAskingTheBrain() async throws {
        let speaker = RecordingSpeaker()
        let link = SlowLink(seconds: 0, answer: try answer())
        let conversation = Conversation(
            link: link, speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        await conversation.heard("Ma'am Knox")
        XCTAssertEqual(speaker.said.count, 1)
        // The first call in a while is greeted for the hour, and the brain's answer is never said.
        XCTAssertTrue(speaker.said[0].hasPrefix("Good "))
    }

    func testSaysTheWordsBeforeAToolCallAsTheirOwnSentence() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"You mean Codex?"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__sessions"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Codex has nothing running."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        await conversation.heard("what is coco doing")
        XCTAssertEqual(speaker.said, ["You mean Codex?", "Codex has nothing running."])
    }

    func testSaysNoLetMeLookBeforeSomethingItDoes() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__watch_for"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"I'll tell you when it finishes."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["Let me look."]
        )
        await conversation.heard("yes please tell me")
        XCTAssertEqual(speaker.said, ["I'll tell you when it finishes."])
    }

    func testSaysLetMeLookTheMomentItStartsLookingSomethingUp() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__changes"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Two files changed."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["Let me look."]
        )
        await conversation.heard("what did it change")
        XCTAssertEqual(speaker.said, ["Let me look.", "Two files changed."])
    }

    func testPutsACardUpAndOpensAWindowWhenAsked() async throws {
        final class RecordingPresenter: Presenter {
            var cards: [String] = []
            var shown: [SummaryCard] = []
            var opened: [DisplayHost?] = []
            var live: [String] = []
            func live(session: String, host: DisplayHost?) async { live.append(session) }
            func focus(session: String, host: DisplayHost?) async -> Typed { live.append("focus \(session)"); return .landed }
            func open(_ host: DisplayHost?) async -> Bool {
                opened.append(host)
                return host != nil
            }
            func card(_ card: SummaryCard) async {
                cards.append("\(card.title): \(card.text)")
                shown.append(card)
            }
            var typed: [String] = []
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed {
                typed.append(text)
                return host?.tty != nil ? .landed : Typed(.failed)
            }
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed {
                typed.append("\(session): \(text)")
                return .landed
            }
            var walks: [WalkCard] = []
            func launch(_ command: String, in folder: String?) async -> Typed {
                typed.append("launch \(folder ?? ""): \(command)")
                return .landed
            }
            func walk(_ walk: WalkCard) async { walks.append(walk) }
            func scan(_ agents: [AgentNode], title: String) async {}
            func trace(_ trace: TraceData, title: String) async {}
            var boards: [String] = []
            func board(title: String) async { boards.append(title) }
        }
        let presenter = RecordingPresenter()
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: []), speaker: speaker, key: PersonKey(),
            face: RecordingFace(), owner: MemoryOwner(nil), presenter: presenter
        )
        let card = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_1","agent":"claude-code","summary":"It added **two** tests.","at":"2026-10-01T00:00:00Z","display":"card","title":"Checkout","files":[{"path":"src/cart.ts","added":3,"removed":1},{"path":"logo.png"}],"excerpt":{"path":"src/cart.ts","lines":["-const a = 1;","+const a = 2;"]}}}"#)
        let open = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_2","agent":"claude-code","summary":"Checkout","at":"2026-10-01T00:00:00Z","display":"open","host":{"app":"iTerm","tty":"ttys004"}}}"#)
        let lost = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_3","agent":"claude-code","summary":"Checkout","at":"2026-10-01T00:00:00Z","display":"open"}}"#)
        for response in [card, open, lost] { await conversation.handle(try XCTUnwrap(response.event)) }
        XCTAssertEqual(presenter.cards, ["Checkout: It added **two** tests."])
        let type = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_4","agent":"claude-code","summary":"push the voice branch","at":"2026-10-01T00:00:00Z","display":"type","host":{"app":"iTerm","tty":"ttys004"}}}"#)
        let prefill = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_5","agent":"claude-code","summary":"add a test","at":"2026-10-01T00:00:00Z","display":"prefill","sessionId":"cb694eae-78b4-439d-adce-edb96cac223e","host":{"app":"Visual Studio Code"}}}"#)
        for response in [type, prefill] { await conversation.handle(try XCTUnwrap(response.event)) }
        XCTAssertEqual(presenter.typed, ["push the voice branch", "cb694eae-78b4-439d-adce-edb96cac223e: add a test"])
        XCTAssertEqual(presenter.shown.first?.files, [CardFile(path: "src/cart.ts", added: 3, removed: 1), CardFile(path: "logo.png")])
        XCTAssertEqual(presenter.shown.first?.excerpt, CardExcerpt(path: "src/cart.ts", lines: ["-const a = 1;", "+const a = 2;"]))
        XCTAssertEqual(presenter.opened.first??.tty, "ttys004")
        XCTAssertEqual(speaker.said, ["My apologies, I could not bring its window forward."])
        let live = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_6","agent":"claude-code","summary":"Checkout","at":"2026-10-01T00:00:00Z","display":"open","sessionId":"ses_live","host":{"app":"Visual Studio Code"}}}"#)
        await conversation.handle(try XCTUnwrap(live.event))
        // A session it knows opens live on screen, rather than jumping straight to another app.
        XCTAssertEqual(presenter.live, ["ses_live"])
        let all = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_7","agent":"memnox","summary":"","at":"2026-10-01T00:00:00Z","display":"sessions","title":"Your sessions"}}"#)
        await conversation.handle(try XCTUnwrap(all.event))
        XCTAssertEqual(presenter.boards, ["Your sessions"])
    }

    func testStartsASessionAndPutsAWalkThroughUp() async throws {
        final class Recording: Presenter {
            var launched: [String] = []
            var walks: [WalkCard] = []
            func live(session: String, host: DisplayHost?) async {}
            func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
            func open(_ host: DisplayHost?) async -> Bool { true }
            func card(_ card: SummaryCard) async {}
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { .landed }
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { .landed }
            func launch(_ command: String, in folder: String?) async -> Typed {
                launched.append("\(folder ?? "nowhere"): \(command)")
                return .landed
            }
            func walk(_ walk: WalkCard) async { walks.append(walk) }
            var scanned: [String] = []
            func scan(_ agents: [AgentNode], title: String) async { scanned = agents.map(\.kind) + [title] }
            func trace(_ trace: TraceData, title: String) async {}
            func board(title: String) async {}
        }
        let presenter = Recording()
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [try line(#"{"id":1,"ok":true,"outcome":"kept"}"#)]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil), presenter: presenter
        )
        let launch = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_7","agent":"claude-code","summary":"memnox run -- claude 'fix it'","at":"2026-10-01T00:00:00Z","display":"launch","host":{"cwd":"/r/memnox-cloud"}}}"#)
        let walk = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_8","agent":"claude-code","summary":"Walk","at":"2026-10-01T00:00:00Z","display":"walk","title":"Card fix","sessionId":"ses_1","pages":[{"path":"src/card.ts","note":"It **stays** flat.","added":2,"lines":["+flat"]}]}}"#)
        for response in [launch, walk] { await conversation.handle(try XCTUnwrap(response.event)) }
        XCTAssertEqual(presenter.launched, ["/r/memnox-cloud: memnox run -- claude 'fix it'"])
        XCTAssertEqual(presenter.walks.first?.title, "Card fix")
        XCTAssertEqual(presenter.walks.first?.pages, [WalkPage(path: "src/card.ts", note: "It stays flat.", added: 2, lines: ["+flat"])])
        XCTAssertEqual(speaker.said, [])
        let scan = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_9","agent":"memnox","summary":"Your agents","at":"2026-10-01T00:00:00Z","display":"agents","title":"Your agents","agents":[{"id":"agt_claude-code","kind":"claude-code","name":"Claude Code","servers":3,"reaches":["shell"],"working":1,"open":0}]}}"#)
        await conversation.handle(try XCTUnwrap(scan.event))
        XCTAssertEqual(presenter.scanned, ["claude-code", "Your agents"])
    }

    func testTellsTheBrainWhenTypingFailedAndOnlySpeaksForAnOlderDaemon() async throws {
        final class FailingPresenter: Presenter {
            func live(session: String, host: DisplayHost?) async {}
            func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
            func open(_ host: DisplayHost?) async -> Bool { false }
            func card(_ card: SummaryCard) async {}
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { Typed(.failed, "no tab") }
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { Typed(.failed) }
            func launch(_ command: String, in folder: String?) async -> Typed { Typed(.failed) }
            func walk(_ walk: WalkCard) async {}
            func scan(_ agents: [AgentNode], title: String) async {}
            func trace(_ trace: TraceData, title: String) async {}
            func board(title: String) async {}
        }
        let type = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_4","agent":"claude-code","summary":"commit it","at":"2026-10-01T00:00:00Z","display":"type","host":{"app":"iTerm","tty":"ttys004"}}}"#).event)
        let heard = RecordingSpeaker()
        let listening = Conversation(
            link: SlowLink(seconds: 0, answer: [try line(#"{"id":1,"ok":true,"outcome":"kept"}"#)]),
            speaker: heard, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil), presenter: FailingPresenter()
        )
        await listening.handle(type)
        // The brain waiting on send_instruction says it, so the app says nothing over it.
        XCTAssertEqual(heard.said, [])
        let older = RecordingSpeaker()
        let unheard = Conversation(
            link: SlowLink(seconds: 0, answer: []),
            speaker: older, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil), presenter: FailingPresenter()
        )
        await unheard.handle(type)
        XCTAssertEqual(older.said, ["My apologies, I could not type it into its terminal."])
    }

    func testSaysHowToLetItTypeOnceAndThenOnlyWhereTheWordsAre() async throws {
        final class LockedPresenter: Presenter {
            func live(session: String, host: DisplayHost?) async {}
            func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
            func open(_ host: DisplayHost?) async -> Bool { false }
            func card(_ card: SummaryCard) async {}
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { Typed(.failed) }
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed {
                Typed(.notAllowed, "Memnox is not allowed to type yet")
            }
            func launch(_ command: String, in folder: String?) async -> Typed { Typed(.failed) }
            func walk(_ walk: WalkCard) async {}
            func scan(_ agents: [AgentNode], title: String) async {}
            func trace(_ trace: TraceData, title: String) async {}
            func board(title: String) async {}
        }
        let prefill = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_5","agent":"claude-code","summary":"check the git history","at":"2026-10-01T00:00:00Z","display":"prefill","sessionId":"ses_1","host":{"app":"Visual Studio Code"}}}"#).event)
        // macOS 27 renamed the pane, so each release hears the name its own System Settings shows.
        for (version, pane) in [(26, "Accessibility"), (27, "Device Control and Data Access")] {
            let speaker = RecordingSpeaker()
            let conversation = Conversation(
                link: SlowLink(seconds: 0, answer: [try line(#"{"id":1,"ok":true,"outcome":"kept"}"#)]),
                speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil), presenter: LockedPresenter(),
                macOSMajorVersion: version
            )
            await conversation.handle(prefill)
            await conversation.handle(prefill)
            XCTAssertEqual(speaker.said.count, 2)
            XCTAssertTrue(speaker.said[0].contains(pane), "macOS \(version)")
            XCTAssertEqual(speaker.said[1], "Your words are on the clipboard again.")
        }
    }

    func testSpeaksUpWithTheBriefAndFallsBackToTheFact() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#)]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        let notice = try line(#"{"id":0,"ok":true,"event":{"kind":"notice","subject":"ntc_1","agent":"claude-code","summary":"Claude Code just made a commit.","at":"2026-10-01T00:00:00Z","notice":"committed"}}"#)
        await conversation.handle(try XCTUnwrap(notice.event))
        XCTAssertEqual(speaker.said, ["Claude Code just made a commit."])
    }

    func testEndsTheConversationWhenTheBrainSaysThePersonIsDone() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__end_conversation"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Right, got it."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["One sec."]
        )
        await conversation.heard("no it's fine")
        XCTAssertEqual(speaker.said, ["Right, got it."])
        XCTAssertTrue(conversation.takeEnd())
        XCTAssertFalse(conversation.takeEnd())
    }

    func testSendsNothingWhenTheRecognizerHeardOnlyPunctuation() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: try answer()),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        await conversation.heard(" . ")
        XCTAssertEqual(speaker.said, [])
    }

    func testNeverSaysLetMeLookTwoTurnsRunning() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__sessions"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Two are working. "}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["One sec."]
        )
        await conversation.heard("what are they doing")
        await conversation.heard("and now")
        XCTAssertEqual(speaker.said.filter { $0 == "One sec." }.count, 1)
    }
}

/// Which events are said, and which keep the microphone open.
final class AnnouncingTests: XCTestCase {
    private func notice(_ kind: String) throws -> DaemonEvent {
        try event(#"{"kind":"notice","notice":"\#(kind)","subject":"ntc_1","agent":"claude-code","summary":"It happened.","at":"2026-10-01T00:00:00Z"}"#)
    }

    func testReadsEveryNoticeTheRuntimeSendsAndANewOneAsUnknown() throws {
        XCTAssertEqual(try notice("would-have").noticeKind, .wouldHave)
        XCTAssertEqual(try notice("collision").noticeKind, .collision)
        XCTAssertNil(try notice("something-newer").noticeKind)
    }

    func testSaysWhatTheyAskedForOrWhatWaitsOnThemWhateverTheSetting() throws {
        for kind in ["watched", "question", "collision"] {
            XCTAssertTrue(try notice(kind).isSaid(speakUp: false), kind)
        }
        for kind in ["finished", "committed", "pushed", "would-have", "ended", "something-newer"] {
            XCTAssertFalse(try notice(kind).isSaid(speakUp: false), kind)
            XCTAssertTrue(try notice(kind).isSaid(speakUp: true), kind)
        }
    }

    func testSaysEverythingThatIsNotANoticeEvenWithSpeakUpOff() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"It wants to push.","at":"2026-10-01T00:00:00Z"}"#)
        XCTAssertTrue(held.isSaid(speakUp: false))
    }

    func testKeepsListeningOnlyForWhatWaitsOnTheirAnswer() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"It wants to push.","at":"2026-10-01T00:00:00Z"}"#)
        XCTAssertTrue(held.awaitsAnswer)
        XCTAssertTrue(try notice("question").awaitsAnswer)
        XCTAssertTrue(try notice("collision").awaitsAnswer)
        XCTAssertFalse(try notice("watched").awaitsAnswer)
        XCTAssertFalse(try notice("finished").awaitsAnswer)
    }
}

/// A held call put the way a colleague would ask it.
final class HeldQuestionTests: XCTestCase {
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
}

/// What a session shows at a glance.
final class SessionStatusTests: XCTestCase {
    func testAPauseOrAQuestionOutranksWhateverTheSessionIsDoing() {
        XCTAssertEqual(SessionStatus(state: .working, thinking: true, paused: true).label, "Paused")
        XCTAssertEqual(SessionStatus(state: .paused, thinking: true).label, "Paused")
        XCTAssertEqual(SessionStatus(state: .working, thinking: true, waitingOnYou: 1).label, "Needs you")
        XCTAssertEqual(SessionStatus(state: .open, thinking: true).label, "Thinking")
    }

    func testNamesEachStateTheWayAPersonSaysIt() {
        XCTAssertEqual(SessionStatus(state: .working, thinking: false).label, "Working")
        XCTAssertEqual(SessionStatus(state: .open, thinking: false).label, "Waiting on you")
        XCTAssertEqual(SessionStatus(state: .ended, thinking: false).label, "Ended")
        XCTAssertEqual(SessionStatus(state: .idle, thinking: false).label, "Quiet")
        XCTAssertEqual(SessionStatus(state: nil, thinking: false).label, "Quiet")
    }

    func testACardAndTheLiveWindowReadTheSameState() {
        let card = SessionCard(sessionId: "ses_1", agentName: "Codex", state: "working")
        XCTAssertEqual(card.sessionState, .working)
        XCTAssertEqual(card.status, .working)
        XCTAssertTrue(card.status.isActive)
        XCTAssertNil(SessionCard(sessionId: "ses_2", agentName: "Codex", state: "something-newer").sessionState)
    }
}

/// How sessions, steps and timings read on screen.
final class SessionTextTests: XCTestCase {
    private func step(_ surface: String, _ text: String) throws -> SessionViewStep {
        try JSONDecoder().decode(SessionViewStep.self, from: Data(#"{"at":"2026-10-01T00:00:00Z","surface":"\#(surface)","text":"\#(text)"}"#.utf8))
    }

    func testSaysHowLongAgoTheWayAPersonDoes() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z"))
        XCTAssertEqual(SessionText.ago("2026-10-03T11:59:30Z", now: now), "just now")
        // Another machine's clock a little ahead is still just now, never a negative minute.
        XCTAssertEqual(SessionText.ago("2026-10-03T12:00:10Z", now: now), "just now")
        XCTAssertEqual(SessionText.ago("2026-10-03T11:59:00Z", now: now), "1 min ago")
        XCTAssertEqual(SessionText.ago("2026-10-03T11:15:00.250Z", now: now), "44 min ago")
        XCTAssertEqual(SessionText.ago("2026-10-03T09:00:00Z", now: now), "3 h ago")
        XCTAssertEqual(SessionText.ago("2026-10-01T12:00:00Z", now: now), "2 d ago")
        XCTAssertNil(SessionText.ago("yesterday", now: now))
        XCTAssertNil(SessionText.ago(nil, now: now))
    }

    func testNamesAHostItReachedBySiteAndAFileByItsLastPart() throws {
        XCTAssertEqual(SessionText.line(for: try step("network", "GET https://api.github.com/repos")), "Reached github.com")
        XCTAssertEqual(SessionText.line(for: try step("filesystem", "Edited /work/shop/src/cart.ts")), "Edited cart.ts")
    }

    func testLeavesOutTheHostsItCalledAndRepeatsUnlessThatIsAllItDid() throws {
        let edit = try step("filesystem", "Edited /work/cart.ts")
        let steps = [edit, try step("network", "GET https://a.example.com"), edit, try step("shell", "Ran npm test")]
        XCTAssertEqual(SessionText.meaningful(steps).map(SessionText.line(for:)), ["Edited cart.ts", "Ran npm test"])
        let onlyCalls = [try step("network", "GET https://example.com")]
        XCTAssertEqual(SessionText.meaningful(onlyCalls).count, 1)
    }

    func testNamesATraceStepAndItsDurationTheWayAWaterfallIsRead() {
        XCTAssertEqual(SessionText.traceStepName("voice.turn"), "Your question")
        XCTAssertEqual(SessionText.traceStepName("brain.sessions"), "Asked sessions")
        XCTAssertEqual(SessionText.traceStepName("operator.show"), "Ran show")
        XCTAssertEqual(SessionText.traceStepName("custom"), "custom")
        XCTAssertEqual(SessionText.duration(milliseconds: 420), "420 ms")
        XCTAssertEqual(SessionText.duration(milliseconds: 1_260), "1.3 s")
        XCTAssertEqual(SessionText.shortPath("/work/shop/src/cart.ts"), "src/cart.ts")
    }

    func testSubtitlesASessionWithWhatTheTitleDidNotSay() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z"))
        let quiet = SessionCard(sessionId: "ses_1", agentName: "Codex", task: "fix the test", state: "idle",
                                repository: "api", lastActive: "2026-10-03T11:50:00Z")
        XCTAssertEqual(quiet.title, "fix the test")
        XCTAssertEqual(quiet.subtitle(now: now), "Codex \u{00B7} api \u{00B7} 10 min ago")
        let busy = SessionCard(sessionId: "ses_2", agentName: "Codex", state: "working", repository: "api")
        XCTAssertEqual(busy.subtitle(now: now), "Codex \u{00B7} working")
    }
}

/// The wire format shared with memnox-runtime, read and written exactly.
final class DaemonProtocolTests: XCTestCase {
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

    func testReadsALiveSessionWithItsConversation() throws {
        let response = try line(#"{"id":7,"ok":true,"session":{"sessionId":"ses_1","agent":"claude-code","agentName":"Claude Code","task":"add a cancel button","state":"working","thinking":true,"waitingOnYou":0,"helpers":[],"steps":[{"at":"t","surface":"git","text":"Pushed main","refused":true}],"files":[{"path":"src/Cart.tsx","added":4,"removed":1}],"conversation":[{"at":"t1","who":"person","text":"add a cancel button"},{"at":"t2","who":"tool","text":"Edit: Cart.tsx"}]}}"#)
        let view = try XCTUnwrap(response.session)
        XCTAssertEqual(view.conversation?.map(\.who), ["person", "tool"])
        XCTAssertEqual(view.steps.first?.refused, true)
        XCTAssertTrue(view.thinking)
    }
}

/// The one line under the orb, and tool names as a person reads them.
final class CaptionTests: XCTestCase {
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

/// Telling the person cutting in from the voice hearing its own echo.
final class EchoTests: XCTestCase {
    func testTakesTheTailOfItsOwnSentenceOffWhatItHeard() {
        let spoken = "My apologies, that was not confirmed: memnox login is not something a voice may run."
        XCTAssertEqual(withoutEchoRuns("Confirmed Memnox login", spoken: spoken), "")
        // One word at an end could be theirs, so it stays.
        XCTAssertEqual(withoutEchoRuns("Yes, login", spoken: spoken), "Yes, login")
    }

    func testTellsThePersonTalkingOverItFromItsOwnEcho() {
        let spoken = "Claude Code finished checkout, four files changed and the tests pass."
        XCTAssertFalse(isBargeIn(heard: "four files changed and the tests", spoken: spoken))
        XCTAssertFalse(isBargeIn(heard: "the", spoken: spoken))
        XCTAssertTrue(isBargeIn(heard: "wait, what about codex", spoken: spoken))
        XCTAssertTrue(isBargeIn(heard: "stop open it", spoken: ""))
    }

    func testHearsThePersonWhoseShortWordsSoundLikeItsOwn() {
        // "so" is a letter from "to" and "them" holds "the": the person, not its echo.
        let spoken = "Two are working at the moment."
        XCTAssertTrue(isBargeIn(heard: "Okay, so can you close all of them?", spoken: spoken, speaking: true))
        XCTAssertEqual(withoutEchoRuns("Okay, so can you close all of them?", spoken: spoken), "Okay, so can you close all of them?")
    }

    func testDoesNotTakeItsOwnSentenceMisheardAtTheEndForThePerson() {
        let spoken = "I missed that. Which repository would you like the session on, and what should it check for?"
        XCTAssertFalse(isBargeIn(heard: "I missed that we were positive", spoken: spoken, speaking: true))
        XCTAssertTrue(isBargeIn(heard: "no the memnox client folder please", spoken: spoken, speaking: true))
    }

    func testDoesNotTakeItsOwnVoiceMisheardForThePerson() {
        XCTAssertFalse(isBargeIn(heard: "Possession is running", spoken: "The session's running but its window isn't tracked", speaking: true))
        XCTAssertFalse(isBargeIn(heard: "Let me log everything", spoken: "Let me look. Everything's quiet.", speaking: true))
        XCTAssertFalse(isBargeIn(heard: "Which one menu bar", spoken: "Which one, MenuBar, Showing, or the renderer tweak?", speaking: true))
        XCTAssertFalse(isBargeIn(heard: "There is", spoken: "There's a card on your screen with the summary.", speaking: true))
        XCTAssertTrue(isBargeIn(heard: "Nothing's working now the fingerprint can you tell me what", spoken: "Nothing's working now. The fingerprint task was the last one.", speaking: true))
        // A long reply heard back first, then the person: the newest words decide, not the whole of it.
        let reply = "I keep an eye on your agent sessions and tell you what each is doing"
        XCTAssertTrue(isBargeIn(heard: "\(reply) wait stop which one is working", spoken: reply, speaking: true))
        XCTAssertFalse(isBargeIn(heard: reply, spoken: reply, speaking: true))
        XCTAssertEqual(withoutEcho("Nothing's working now the fingerprint can you tell me what", spoken: "Nothing's working now. The fingerprint task was the last one."), "can you tell me what")
    }

    func testStopOrWaitCutsInAtOnceButItsOwnWordsNeverDo() {
        let spoken = "Claude Code has been building the voice bridge for the Mac app"
        XCTAssertTrue(isBargeIn(heard: "Claude Code has been shut up", spoken: spoken, speaking: true))
        XCTAssertTrue(isBargeIn(heard: "stop", spoken: spoken, speaking: true))
        XCTAssertTrue(isBargeIn(heard: "wait", spoken: spoken, speaking: true))
        // Its own words echoed back are never the person, even when they are long.
        XCTAssertFalse(isBargeIn(heard: "the voice bridge for the Mac", spoken: spoken, speaking: true))
        // It said "stop" itself, so hearing "stop" is its own echo.
        XCTAssertFalse(isBargeIn(heard: "stop", spoken: "I can stop the session", speaking: true))
    }
}

/// A card summary laid out as blocks the way it was written.
final class MarkdownBlocksTests: XCTestCase {
    func testLaysOutASummaryAsWritten() {
        let blocks = MarkdownBlock.parse("""
        ## Pushed the voice branch

        - Ran `pnpm test`, **all green**
        1. Committed six times
        ```
        git push origin feat/voice-answers
        ```
        It is waiting on you now.
        """)
        XCTAssertEqual(blocks, [
            .heading("Pushed the voice branch"),
            .bullet("Ran `pnpm test`, **all green**"),
            .bullet("Committed six times"),
            .code("git push origin feat/voice-answers"),
            .text("It is waiting on you now."),
        ])
    }

    func testKeepsAnUnclosedFenceAsCode() {
        XCTAssertEqual(MarkdownBlock.parse("```\nnpm test"), [.code("npm test")])
        XCTAssertEqual(MarkdownBlock.parse("#hashtag"), [.text("#hashtag")])
    }

    func testNeverCallsARunningLoginDone() {
        XCTAssertEqual(Conversation.afterConfirm(.confirmed, outcome: "started"),
                       "Very well. It is under way, and I will tell you if anything goes wrong.")
        XCTAssertEqual(Conversation.afterConfirm(.confirmed, outcome: "confirmed"), "Very well. It is done.")
        XCTAssertEqual(Conversation.afterConfirm(.declined, outcome: nil), "Very well. I have left it as it was.")
    }
}

/// The words of an agent's world, said the way a person says them.
final class PronounceTests: XCTestCase {
    func testReadsTheWordsOfAnAgentsWorldTheWayAPersonSaysThem() {
        XCTAssertEqual(pronounced("Run npm publish from the CLI."), "Run N P M publish from the C L I.")
        XCTAssertEqual(pronounced("It changed Speech.swift and packages/cli/src/show-tool.ts."), "It changed Speech dot swift and show tool dot T S.")
        XCTAssertEqual(pronounced("Turn it on with memnox protect --enforce."), "Turn it on with memnox protect dash dash enforce.")
        XCTAssertEqual(pronounced("Claude Code in memnox-runtime opened two PRs."), "Claude Code in memnox runtime opened two P R's.")
        XCTAssertEqual(pronounced("The UI in VS Code reads the MCP config."), "The U I in V S Code reads the M C P config.")
        XCTAssertEqual(pronounced("OK, I'll check the JSON."), "okay, I'll check the Jason.")
        XCTAssertEqual(pronounced("A rule in memnox.policies.toml."), "A rule in memnox dot policies dot tommel.")
        XCTAssertEqual(pronounced("It spent 3.5 minutes on it."), "It spent 3.5 minutes on it.")
        XCTAssertEqual(pronounced("Five agents: Codex CLI and Cursor."), "Five agents: Codex and Cursor.")
        XCTAssertEqual(pronounced("It is on feat/voice-answers."), "It is on feature voice answers.")
        XCTAssertEqual(pronounced("It made e0634ce4 on main."), "It made commit on main.")
        XCTAssertEqual(pronounced("Memnox 0.13.8 shipped."), "Memnox 0 point 13 point 8 shipped.")
        XCTAssertEqual(pronounced("The brain took 640ms in iTerm."), "The brain took 640 milliseconds in eye term.")
        XCTAssertEqual(pronounced("It reviewed PR #88 at https://github.com/memnox/runtime/pull/88."), "It reviewed P R number 88 at github dot com.")
        XCTAssertEqual(pronounced("Run pnpm test in zsh."), "Run P N P M test in Z shell.")
    }
}

/// Streamed text cut into the sentences the voice speaks.
final class SentenceSplitterTests: XCTestCase {
    func testSpeaksWholeSentencesAsTheyArrive() {
        var splitter = SentenceSplitter()
        XCTAssertEqual(splitter.push("Two sessions are "), [])
        XCTAssertEqual(splitter.push("open. Which one? Checkout"), ["Two sessions are open."])
        XCTAssertEqual(splitter.push(" or api"), [])
        // "Which one?" is too short to say alone, so it runs on into what follows it.
        XCTAssertEqual(splitter.flush(), "Which one? Checkout or api")
    }

    func testSaysAShortSentenceTogetherWithTheNext() {
        var splitter = SentenceSplitter()
        XCTAssertEqual(splitter.push("Proposed. It needs your Touch ID on the Mac. "), ["Proposed. It needs your Touch ID on the Mac."])
    }

    func testANumberIsNotTheEndOfASentence() {
        var splitter = SentenceSplitter()
        XCTAssertEqual(splitter.push("It spent 3.5 minutes. Then"), ["It spent 3.5 minutes."])
    }

    func testTheFirstPieceOfAReplyIsSaidAtItsFirstClause() {
        var splitter = SentenceSplitter()
        // A courtesy too short to say alone waits, then the first clause long enough goes at once.
        XCTAssertEqual(splitter.push("Very well, sir. I have opened the Claude session, "), ["Very well, sir. I have opened the Claude session,"])
        // After that only whole sentences, since the rest streams in while the first is spoken.
        XCTAssertEqual(splitter.push("and the tests pass, which is the point. Shall"), ["and the tests pass, which is the point."])
        XCTAssertEqual(splitter.flush(), "Shall")
        // A number's comma has no space after it, so it never ends a piece.
        XCTAssertEqual(splitter.push("It changed 1,200 lines in two files"), [])
    }
}

/// Text made fit to say: no markdown, and a pause where a dash stood.
final class SpeakableTests: XCTestCase {
    func testSpeaksNoMarkdownAndPausesWhereADashStood() {
        XCTAssertEqual(speakable("It's stuck on `git symbolic-ref` \u{2014} **again**."), "It's stuck on git symbolic-ref, again.")
    }
}

/// How long a pause ends what somebody says, and when a guess may start early.
final class TurnTakingTests: XCTestCase {
    func testWaitsLongerWhenSomebodyTrailsOff() {
        XCTAssertEqual(endOfSpeechPause(after: "What are my agents doing?"), 0.9)
        XCTAssertEqual(endOfSpeechPause(after: "what are my agents doing"), 1.7)
        XCTAssertEqual(endOfSpeechPause(after: "Okay, so are you able to uh"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "Can Claude Code connect to"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "My..."), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "OK so I was working on the feature and"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "I wanted to know about my"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "Yes."), 0.6)
        XCTAssertEqual(endOfSpeechPause(after: "Go ahead."), 0.6)
        // Somebody explaining pauses between sentences, so the first one is not answered alone.
        XCTAssertEqual(endOfSpeechPause(after: "Can you open Cursor and start a new session within Memnox runtime and check the git status?"), 1.5)
        XCTAssertEqual(endOfSpeechPause(after: "Can you scan my entire computer and tell me?"), 1.5)
        XCTAssertEqual(endOfSpeechPause(after: "Open the last one."), 0.9)
    }

    func testGuessesAtAPauseOnlyBeforeItEndsWhatTheySaid() {
        // A finished question pauses long enough to start the answer, and is not over yet.
        XCTAssertTrue(mayGuess("What is Claude doing?", pausedFor: 0.4))
        // Too soon, and past the end, there is nothing to guess.
        XCTAssertFalse(mayGuess("What is Claude doing?", pausedFor: 0.2))
        XCTAssertFalse(mayGuess("What is Claude doing?", pausedFor: 1.0))
        // Trailing off on "and" is the middle of a thought, never worth an answer.
        XCTAssertFalse(mayGuess("Open the Claude session and", pausedFor: 0.6))
        XCTAssertFalse(mayGuess("", pausedFor: 0.6))
    }
}

/// What it says back when called by name.
final class WakeLinesTests: XCTestCase {
    func testGreetsTheFirstCallInAWhileForTheHourAndNeverRepeatsALine() {
        var lines = WakeLines()
        let first = { (choices: [String]) in choices.first }
        XCTAssertEqual(lines.line(address: "sir", hour: 20, sinceLastCall: nil, pick: first), "Good evening, sir. How shall we proceed?")
        XCTAssertEqual(lines.line(address: nil, hour: 8, sinceLastCall: 5 * 60 * 60, pick: first), "Good morning. How shall we proceed?")
        // Called again soon after, a word or two, and never the line said last.
        XCTAssertEqual(lines.line(address: "sir", hour: 20, sinceLastCall: 30, pick: first), "Yes, sir?")
        XCTAssertEqual(lines.line(address: "sir", hour: 20, sinceLastCall: 30, pick: first), "Sir?")
        // No address chosen, no honorific guessed.
        XCTAssertFalse(lines.line(address: "  ", hour: 20, sinceLastCall: 30).contains("sir"))
    }
}

/// Hearing its name, however the recognizer spells it, and what follows it.
final class WakeWordTests: XCTestCase {
    func testWakesOnItsNameAndHandsOnWhatFollowed() {
        XCTAssertEqual(afterWakeWord("Memnox"), "")
        XCTAssertEqual(afterWakeWord("Hey Memnox, what's going on?"), "what's going on?")
        XCTAssertEqual(afterWakeWord("mem nox are they done"), "are they done")
        XCTAssertEqual(afterWakeWord("Men knocks."), "")
        XCTAssertNil(afterWakeWord("what are my agents doing"))
        XCTAssertNil(afterWakeWord("the memo knocks twice"))
        XCTAssertEqual(afterWakeWord("Ma'am Knox"), "")
        XCTAssertEqual(afterWakeWord("ma'am knox what changed"), "what changed")
    }

    func testWakesOnTheWaysItsNameWasMisheard() {
        XCTAssertEqual(afterWakeWord("Emma Knox, can you start a session?"), "can you start a session?")
        XCTAssertEqual(afterWakeWord("MM Nox. Can you open up all my sessions?"), "Can you open up all my sessions?")
        XCTAssertNotNil(afterWakeWord("Minnox"))
    }

    func testTakesItsNameAtTheEndOfAQuestionAsPartOfTheQuestion() {
        XCTAssertTrue(nameAlone("Memnox"))
        XCTAssertTrue(nameAlone("Hey Memnox."))
        XCTAssertFalse(nameAlone("Can you open Codex and start a new session within Memnox?"))
    }

    func testTakesItsNameOffTheFrontButNotFromTheMiddle() {
        XCTAssertEqual(withoutLeadingName("Mem Nox. I've closed it."), "I've closed it.")
        XCTAssertEqual(withoutLeadingName("Hey Memnox, which one is working?"), "which one is working?")
        XCTAssertEqual(withoutLeadingName("is the Memnox runtime on main"), "is the Memnox runtime on main")
        XCTAssertEqual(withoutLeadingName("Memnox"), "Memnox")
    }
}

/// Bytes from the socket cut into whole protocol lines.
final class LineSplitterTests: XCTestCase {
    func testSplitsLinesAcrossReads() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.push(Data("{\"a\":1}\n{\"b\"".utf8)), ["{\"a\":1}"])
        XCTAssertEqual(splitter.push(Data(":2}\n\n".utf8)), ["{\"b\":2}"])
    }
}

/// The person's name kept in the app's own defaults.
final class DefaultsOwnerTests: XCTestCase {
    func testRemembersTheNameInTheAppsOwnDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "memnox-owner-test-\(UUID().uuidString)"))
        let owner = DefaultsOwner(defaults: defaults)
        XCTAssertNil(owner.name)
        owner.name = "Moise"
        XCTAssertEqual(DefaultsOwner(defaults: defaults).name, "Moise")
    }
}

/// The in memory key signs in the shapes the runtime verifies.
final class SoftwareConfirmKeyTests: XCTestCase {
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
