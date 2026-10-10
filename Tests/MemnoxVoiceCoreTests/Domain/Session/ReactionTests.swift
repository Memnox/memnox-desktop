import XCTest

@testable import MemnoxVoiceCore

/// What the orb does at each fact from the daemon, celebrating only checked work.
final class ReactionTests: XCTestCase {
    private func finished(_ tests: String?) throws -> DaemonEvent {
        let verdict = tests.map { #","tests":"\#($0)""# } ?? ""
        return try event(#"{"kind":"notice","notice":"finished","subject":"ntc_1","agent":"a","summary":"s","at":"t""# + verdict + "}")
    }

    func testBurstsOnlyForATurnThatEndedOnPassingTests() throws {
        XCTAssertEqual(reaction(to: try finished("passed")), .burst)
        XCTAssertEqual(reaction(to: try finished("failed")), .stumble)
    }

    func testOnlyMarksATurnNothingChecked() throws {
        XCTAssertEqual(reaction(to: try finished("stale")), .settle)
        XCTAssertEqual(reaction(to: try finished("none")), .settle)
        // An older daemon sends no verdict, which is no evidence, never a pass.
        XCTAssertEqual(reaction(to: try finished(nil)), .settle)
    }

    func testStumblesWhenASessionPausesOrTwoAgentsMeet() throws {
        XCTAssertEqual(reaction(to: try event(#"{"kind":"paused","subject":"ses_1","agent":"a","summary":"s","at":"t"}"#)), .stumble)
        XCTAssertEqual(reaction(to: try event(#"{"kind":"notice","notice":"collision","subject":"n","agent":"a","summary":"s","at":"t"}"#)), .stumble)
    }

    func testLeavesWhatTheVoiceOrACardAnswers() throws {
        XCTAssertNil(reaction(to: try event(#"{"kind":"held","subject":"apr_1","agent":"a","summary":"s","at":"t"}"#)))
        XCTAssertNil(reaction(to: try event(#"{"kind":"notice","notice":"question","subject":"n","agent":"a","summary":"s","at":"t"}"#)))
    }
}
