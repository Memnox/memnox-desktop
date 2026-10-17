import XCTest

@testable import MemnoxVoiceCore

/// Hearing the person start to talk over the voice by loudness, whatever they say.
final class TalkOverTests: XCTestCase {
    /// Its own voice from the speakers, rising and falling with each syllable.
    private let echo: [Float] = (0..<60).map { 0.38 + 0.12 * Float($0 % 5) / 4 }

    func testHearsThemTheMomentTheyAreLouderThanItsOwnVoice() {
        let ceiling = TalkOver.echoCeiling(echo, lastTime: nil)
        XCTAssertEqual(ceiling, 0.5, accuracy: 0.001)
        XCTAssertTrue(TalkOver.isTalkingOver([0.45, 0.66, 0.7, 0.64, 0.68], echo: ceiling))
    }

    func testNeverTakesItsOwnLoudestSyllableOrAClickForThem() {
        let ceiling = TalkOver.echoCeiling(echo, lastTime: nil)
        XCTAssertFalse(TalkOver.isTalkingOver([0.5, 0.48, 0.5, 0.47, 0.5], echo: ceiling))
        // One loud buffer is a click or a cough, not somebody talking.
        XCTAssertFalse(TalkOver.isTalkingOver([0.4, 0.9, 0.4, 0.42, 0.4], echo: ceiling))
    }

    func testHearsAnyVoiceAtAllWhenNothingComesBackThroughHeadphones() {
        let quiet: [Float] = Array(repeating: 0.08, count: 40)
        let ceiling = TalkOver.echoCeiling(quiet, lastTime: nil)
        XCTAssertTrue(TalkOver.isTalkingOver([0.3, 0.35, 0.32, 0.31, 0.3], echo: ceiling))
    }

    func testStartsFromHowLoudItCameBackLastTimeUntilItHasHeardEnough() {
        XCTAssertEqual(TalkOver.echoCeiling([0.2, 0.3], lastTime: 0.12), 0.3)
        XCTAssertEqual(TalkOver.echoCeiling([0.2], lastTime: nil), TalkOver.unheardEcho)
    }

    func testHearsThePersonOverItsOwnVoiceByWhatItIsPlaying() {
        let own = (0..<TalkOver.enoughLooks).map { _ in TalkOver.Heard(heard: 0.5 - 0.1, playing: 0.5) }
        let gap = TalkOver.ownVoiceGap(own, lastTime: nil)
        XCTAssertEqual(gap ?? 0, -0.1, accuracy: 0.001)
        // Its own voice at full volume comes back no louder than it always does.
        XCTAssertFalse(TalkOver.isOverOwnVoice(own + [.init(heard: 0.6, playing: 0.7), .init(heard: 0.6, playing: 0.7)], gap: gap ?? 0, talking: 0.3))
        // Somebody talking while it plays quietly, or between its words.
        XCTAssertTrue(TalkOver.isOverOwnVoice(own + [.init(heard: 0.6, playing: 0.2), .init(heard: 0.6, playing: 0.1)], gap: gap ?? 0, talking: 0.3))
        // The tail of its last word heard as it falls quiet is still its own.
        XCTAssertFalse(TalkOver.isOverOwnVoice(own + [.init(heard: 0.55, playing: 0.6), .init(heard: 0.5, playing: 0)], gap: gap ?? 0, talking: 0.3))
        // Nothing learned and nothing from last time is never a guess.
        XCTAssertNil(TalkOver.ownVoiceGap([], lastTime: nil))
    }

    func testTrustsNoLoudnessJustAfterItsVoiceComesBack() {
        // The player's meter reads silence for a moment after a resume while its echo is already loud.
        XCTAssertFalse(TalkOver.mayPauseOnLoudness(voiceOnFor: 0.2, loudLooks: 5, cancellingEcho: true))
        XCTAssertTrue(TalkOver.mayPauseOnLoudness(voiceOnFor: 1, loudLooks: 1, cancellingEcho: true))
    }

    func testWantsLoudnessToHoldWithoutEchoCancellation() {
        XCTAssertFalse(TalkOver.mayPauseOnLoudness(voiceOnFor: 2, loudLooks: 1, cancellingEcho: false))
        XCTAssertTrue(TalkOver.mayPauseOnLoudness(voiceOnFor: 2, loudLooks: TalkOver.loudLooksUncancelled, cancellingEcho: false))
    }

    func testNeverCarriesOnOverSomebodyStillTalking() {
        XCTAssertFalse(TalkOver.mayCarryOn(pausedFor: 2, quietFor: 0.1))
        XCTAssertTrue(TalkOver.mayCarryOn(pausedFor: 2, quietFor: TalkOver.quietToCarryOn))
    }

    func testCarriesOnSoonOnceTheRoomIsQuietButNotBeforeTheRecognizerCatchesUp() {
        XCTAssertFalse(TalkOver.mayCarryOn(pausedFor: 0.5, quietFor: 0.5))
        XCTAssertTrue(TalkOver.mayCarryOn(pausedFor: TalkOver.shortestHold, quietFor: 1))
    }

    func testCarriesOnAfterAWhileOfNoiseWithNoWordsInIt() {
        XCTAssertTrue(TalkOver.mayCarryOn(pausedFor: TalkOver.longestHold, quietFor: 0))
    }
}
