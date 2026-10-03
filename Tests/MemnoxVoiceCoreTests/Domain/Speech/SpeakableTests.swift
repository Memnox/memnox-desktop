import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Text made fit to say: no markdown, and a pause where a dash stood.
final class SpeakableTests: XCTestCase {
    func testSpeaksNoMarkdownAndPausesWhereADashStood() {
        XCTAssertEqual(speakable("It's stuck on `git symbolic-ref` \u{2014} **again**."), "It's stuck on git symbolic-ref, again.")
    }
}
