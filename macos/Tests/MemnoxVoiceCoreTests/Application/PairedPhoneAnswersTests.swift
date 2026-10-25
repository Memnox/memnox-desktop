import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A paired phone answers every yes with Face ID, since the person who paired it may be far from this Mac.
final class PairedPhoneAnswersTests: XCTestCase {
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
        conversation = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner("Maya"))
    }

    private let paired = #","answerOn":{"deviceId":"dev_1","name":"Sam's iPhone"}"#

    func testASpokenYesIsLeftToThePairedPhoneAndSaidRatherThanPutToTouchID() async throws {
        await conversation.heard("yes go ahead")
        await conversation.handle(try event(#"{"kind":"proposal","subject":"prp_9","agent":"a","summary":"push to main","at":"t""# + paired + "}"))

        XCTAssertEqual(key.signed, [])
        XCTAssertFalse(link.sent.contains { $0.method == "confirm" })
        XCTAssertEqual(speaker.said.last, "Answer it on Sam's iPhone, which asks for Face ID.")
        XCTAssertFalse(face.states.contains(.needsYou))
    }

    func testAPressOnTheIslandStillTakesTouchIDWhileThePhoneIsOnlyPaired() async throws {
        await conversation.handle(try event(#"{"kind":"proposal","subject":"prp_9","agent":"a","summary":"push to main","at":"t""# + paired + "}"))
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"once"}"#)]
        let outcome = await conversation.answerHeld("apr_4", .once, reason: "push to main")

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:apr_4:once"])
    }

    func testAMacProposalAPhoneAskedForIsLeftForItWhateverHoldsTheVoice() async throws {
        await conversation.heard("type it in")
        await conversation.handle(try event(#"{"kind":"proposal","subject":"prp_7","agent":"memnox","summary":"Type into Claude Code","at":"t","origin":{"deviceId":"dev_1"}}"#))

        XCTAssertEqual(key.signed, [])
        XCTAssertTrue(link.sent.allSatisfy { $0.method != "confirm" })
    }

    func testThisMacsOwnDeviceIdIsNeverTakenForAPhone() async throws {
        OwnDevices.shared.set(["dev_mac"])
        defer { OwnDevices.shared.set([]) }
        let own = try event(#"{"kind":"proposal","subject":"prp_9","agent":"a","summary":"s","at":"t","answerOn":{"deviceId":"dev_mac","name":"Mac"}}"#)
        XCTAssertNil(conversation.phoneFor(own))
        XCTAssertEqual(conversation.phoneFor(try event(#"{"kind":"held","subject":"apr_1","agent":"a","summary":"s","at":"t""# + paired + "}")), "Sam's iPhone")
    }

    func testWithNoPhonePairedASpokenYesStillAsksTouchID() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"confirmed"}"#)]
        await conversation.heard("yes go ahead")
        await conversation.handle(try event(#"{"kind":"proposal","subject":"prp_9","agent":"a","summary":"push to main","at":"t"}"#))

        XCTAssertEqual(key.signed, ["memnox-confirm:v1:prp_9:confirmed"])
    }
}
