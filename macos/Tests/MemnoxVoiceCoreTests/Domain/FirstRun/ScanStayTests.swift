import XCTest

@testable import MemnoxVoiceCore

final class ScanStayTests: XCTestCase {
    func testStaysPastTheSilentCapWhileTheVoiceIsStillExplaining() {
        XCTAssertFalse(ScanStay.closes(shownFor: ScanStay.silentCap * 3, voiceStarted: true, narratedFor: nil))
    }

    func testClosesAMomentAfterTheLastWordRatherThanOnIt() {
        XCTAssertFalse(ScanStay.closes(shownFor: 40, voiceStarted: true, narratedFor: 0))
        XCTAssertTrue(ScanStay.closes(shownFor: 40, voiceStarted: true, narratedFor: ScanStay.afterNarration))
    }

    func testANarrationThatNeverStartsFallsBackToTheSilentCap() {
        XCTAssertFalse(ScanStay.closes(shownFor: ScanStay.silentCap - 1, voiceStarted: false, narratedFor: nil))
        XCTAssertTrue(ScanStay.closes(shownFor: ScanStay.silentCap, voiceStarted: false, narratedFor: nil))
    }

    func testAMutedVoiceStillLeavesTheScreenUpLongEnoughToRead() {
        XCTAssertFalse(ScanStay.closes(shownFor: 1, voiceStarted: false, narratedFor: 1))
        XCTAssertTrue(ScanStay.closes(shownFor: ScanStay.silentCap, voiceStarted: false, narratedFor: ScanStay.silentCap))
    }
}
