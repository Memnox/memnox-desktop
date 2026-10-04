import Foundation
import XCTest

@testable import MemnoxVoiceCore

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

    func testAllowsAHeldCallInsideTheSessionFromAButtonWithNoTouchID() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"once"}"#)]
        let outcome = await conversation.answerHeld("apr_4", .once, reason: "delete old.ts", touchID: false)

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, [])
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.answer, "once")
        XCTAssertNil(sent.signature)
        XCTAssertFalse(face.states.contains(.needsYou))
    }

    func testConfirmsASpokenYesInsideTheSessionWithNoTouchID() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"confirmed"}"#)]
        await conversation.heard("yes delete it")
        let proposal = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"proposal","subject":"prp_9","agent":"a","summary":"delete old.ts","at":"t","withinSession":true}}"#).event)
        await conversation.handle(proposal)

        XCTAssertEqual(key.signed, [])
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.answer, "confirmed")
        XCTAssertNil(sent.signature)
        XCTAssertFalse(face.states.contains(.needsYou))
    }

    func testAsksTouchIDWhenTheDaemonDidNotPlaceTheCallInside() throws {
        let outside = try event(#"{"kind":"held","subject":"apr_4","agent":"a","summary":"s","at":"t"}"#)
        let inside = try event(#"{"kind":"held","subject":"apr_4","agent":"a","summary":"s","at":"t","withinSession":true}"#)

        XCTAssertTrue(outside.needsTouchID)
        XCTAssertFalse(inside.needsTouchID)
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
        XCTAssertFalse(link.sent.contains { $0.method == "confirm" })
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

    func testReadsTheVoiceAgentsAndWhyTheOthersCannotAnswer() async throws {
        link.answers["voice-agents"] = [try line(#"{"id":1,"ok":true,"voiceAgents":[{"kind":"cursor","label":"Cursor","installed":true,"sealed":true,"works":true,"chosen":true,"install":"x"},{"kind":"hermes","label":"Hermes","installed":true,"sealed":false,"works":false,"because":"its plan ran out","chosen":false,"install":"y"}]}"#)]
        let answer = await conversation.voiceAgents()
        guard case .agents(let agents) = answer else { return XCTFail("expected agents, got \(answer)") }
        XCTAssertEqual(agents.map(\.kind), ["cursor", "hermes"])
        XCTAssertEqual(agents.last?.because, "its plan ran out")
        XCTAssertNil(link.sent.last?.recheck)
    }

    func testAsksEveryAgentAgainOnlyWhenToldTo() async throws {
        link.answers["voice-agents"] = [try line(#"{"id":1,"ok":true,"voiceAgents":[]}"#)]
        _ = await conversation.voiceAgents(recheck: true)
        XCTAssertEqual(link.sent.last?.recheck, true)
    }

    func testSendsThePersonsPickAndSaysWhyOneWasRefused() async throws {
        link.answers["choose-voice-agent"] = [try line(#"{"id":1,"ok":false,"error":"Codex is not installed on this Mac"}"#)]
        let answer = await conversation.chooseVoiceAgent("codex")
        XCTAssertEqual(link.sent.last?.voiceAgent, "codex")
        XCTAssertEqual(answer, .refused("Codex is not installed on this Mac"))
    }

    func testCallsADaemonWithNoVoiceAgentsOlderRatherThanEmpty() async throws {
        link.answers["voice-agents"] = [try line(#"{"id":1,"ok":true}"#)]
        let answer = await conversation.voiceAgents()
        XCTAssertEqual(answer, .refused("This Memnox is older than the app"))
        link.unreachable = true
        let gone = await conversation.voiceAgents()
        XCTAssertEqual(gone, .unreachable)
    }

    func testReadsTheVoiceAgentsAndWhyTheOthersCannotAnswer() async throws {
        link.answers["voice-agents"] = [try line(#"{"id":1,"ok":true,"voiceAgents":[{"kind":"cursor","label":"Cursor","installed":true,"sealed":true,"works":true,"chosen":true,"install":"x"},{"kind":"hermes","label":"Hermes","installed":true,"sealed":false,"works":false,"because":"its plan ran out","chosen":false,"install":"y"}]}"#)]
        let answer = await conversation.voiceAgents()
        guard case .agents(let agents) = answer else { return XCTFail("expected agents, got \(answer)") }
        XCTAssertTrue(speaker.said.first?.hasPrefix("Memnox trusts another key") ?? false)
    }

    func testAsksNoFingerprintWhileTheDaemonTrustsAnotherKey() async throws {
        // A fingerprint the daemon would refuse is the button doing nothing, so it is never asked for.
        link.answers["register-key"] = [try line(#"{"id":1,"ok":false,"outcome":"another key"}"#)]
        let outcome = await conversation.answerHeld("apr_4", .once, reason: "push to main")

        XCTAssertEqual(outcome, .failed(Conversation.anotherKeyLine))
        XCTAssertEqual(key.signed, [])
        XCTAssertFalse(link.sent.contains { $0.method == "confirm" })
        XCTAssertEqual(speaker.said, [Conversation.anotherKeyLine])
    }

    func testSaysWhyAnAnswerDidNotGoThrough() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":false,"error":"apr_4 is no longer held"}"#)]
        let outcome = await conversation.answerHeld("apr_4", .once, reason: "push to main")

        XCTAssertEqual(outcome, .failed("apr_4 is no longer held"))
        XCTAssertTrue(speaker.said.first?.hasPrefix("That did not go through") ?? false)
        XCTAssertEqual(agents.last?.because, "its plan ran out")
        XCTAssertNil(link.sent.last?.recheck)
    }

    func testAsksEveryAgentAgainOnlyWhenToldTo() async throws {
        link.answers["voice-agents"] = [try line(#"{"id":1,"ok":true,"voiceAgents":[]}"#)]
        _ = await conversation.voiceAgents(recheck: true)
        XCTAssertEqual(link.sent.last?.recheck, true)
    }

    func testSendsThePersonsPickAndSaysWhyOneWasRefused() async throws {
        link.answers["choose-voice-agent"] = [try line(#"{"id":1,"ok":false,"error":"Codex is not installed on this Mac"}"#)]
        let answer = await conversation.chooseVoiceAgent("codex")
        XCTAssertEqual(link.sent.last?.voiceAgent, "codex")
        XCTAssertEqual(answer, .refused("Codex is not installed on this Mac"))
    }

    func testCallsADaemonWithNoVoiceAgentsOlderRatherThanEmpty() async throws {
        link.answers["voice-agents"] = [try line(#"{"id":1,"ok":true}"#)]
        let answer = await conversation.voiceAgents()
        XCTAssertEqual(answer, .refused("This Memnox is older than the app"))
        link.unreachable = true
        let gone = await conversation.voiceAgents()
        XCTAssertEqual(gone, .unreachable)
    }

    func testReadsTheVoiceAgentsAndWhyTheOthersCannotAnswer() async throws {
        link.answers["voice-agents"] = [try line(#"{"id":1,"ok":true,"voiceAgents":[{"kind":"cursor","label":"Cursor","installed":true,"sealed":true,"works":true,"chosen":true,"install":"x"},{"kind":"hermes","label":"Hermes","installed":true,"sealed":false,"works":false,"because":"its plan ran out","chosen":false,"install":"y"}]}"#)]
        let answer = await conversation.voiceAgents()
        guard case .agents(let agents) = answer else { return XCTFail("expected agents, got \(answer)") }
        XCTAssertTrue(speaker.said.first?.hasPrefix("Memnox trusts another key") ?? false)
    }

    func testAsksNoFingerprintWhileTheDaemonTrustsAnotherKey() async throws {
        // A fingerprint the daemon would refuse is the button doing nothing, so it is never asked for.
        link.answers["register-key"] = [try line(#"{"id":1,"ok":false,"outcome":"another key"}"#)]
        let outcome = await conversation.answerHeld("apr_4", .once, reason: "push to main")

        XCTAssertEqual(outcome, .failed(Conversation.anotherKeyLine))
        XCTAssertEqual(key.signed, [])
        XCTAssertFalse(link.sent.contains { $0.method == "confirm" })
        XCTAssertEqual(speaker.said, [Conversation.anotherKeyLine])
    }

    func testSaysWhyAnAnswerDidNotGoThrough() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":false,"error":"apr_4 is no longer held"}"#)]
        let outcome = await conversation.answerHeld("apr_4", .once, reason: "push to main")

        XCTAssertEqual(outcome, .failed("apr_4 is no longer held"))
        XCTAssertTrue(speaker.said.first?.hasPrefix("That did not go through") ?? false)
        XCTAssertEqual(agents.last?.because, "its plan ran out")
        XCTAssertNil(link.sent.last?.recheck)
    }

    func testAsksEveryAgentAgainOnlyWhenToldTo() async throws {
        link.answers["voice-agents"] = [try line(#"{"id":1,"ok":true,"voiceAgents":[]}"#)]
        _ = await conversation.voiceAgents(recheck: true)
        XCTAssertEqual(link.sent.last?.recheck, true)
    }

    func testSendsThePersonsPickAndSaysWhyOneWasRefused() async throws {
        link.answers["choose-voice-agent"] = [try line(#"{"id":1,"ok":false,"error":"Codex is not installed on this Mac"}"#)]
        let answer = await conversation.chooseVoiceAgent("codex")
        XCTAssertEqual(link.sent.last?.voiceAgent, "codex")
        XCTAssertEqual(answer, .refused("Codex is not installed on this Mac"))
    }

    func testCallsADaemonWithNoVoiceAgentsOlderRatherThanEmpty() async throws {
        link.answers["voice-agents"] = [try line(#"{"id":1,"ok":true}"#)]
        let answer = await conversation.voiceAgents()
        XCTAssertEqual(answer, .refused("This Memnox is older than the app"))
        link.unreachable = true
        let gone = await conversation.voiceAgents()
        XCTAssertEqual(gone, .unreachable)
    }

    func testSaysSoWhenAnotherKeyIsRegistered() async throws {
        link.answers["register-key"] = [try line(#"{"id":1,"ok":false,"outcome":"another key"}"#)]
        await conversation.introduce()
        XCTAssertEqual(link.sent.first?.point, key.publicPoint)
        XCTAssertTrue(speaker.said.first?.hasPrefix("Another key is registered") ?? false)
    }
}
