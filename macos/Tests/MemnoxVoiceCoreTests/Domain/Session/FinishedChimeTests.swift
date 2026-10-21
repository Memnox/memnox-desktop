import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A finished session is heard only by somebody who is not already looking at it.
final class FinishedChimeTests: XCTestCase {
    private let iterm = DisplayHost(app: "iTerm2", appPath: "/Applications/iTerm.app")

    func testStaysQuietWhileTheSessionsAppIsInFront() {
        XCTAssertFalse(chimesFinish(runningIn: iterm, frontApp: "iTerm2", frontPath: "/Applications/iTerm.app"))
    }

    func testKnowsTheAppByItsPathWhateverItIsCalled() {
        XCTAssertFalse(chimesFinish(runningIn: iterm, frontApp: "iTerm", frontPath: "/Applications/iTerm.app/"))
    }

    func testKnowsTheAppByItsNameWhenThePathIsMissing() {
        XCTAssertFalse(chimesFinish(runningIn: DisplayHost(app: "Cursor"), frontApp: "cursor", frontPath: nil))
    }

    func testChimesWhileTheyAreSomewhereElse() {
        XCTAssertTrue(chimesFinish(runningIn: iterm, frontApp: "Safari", frontPath: "/Applications/Safari.app"))
    }

    func testChimesForASessionThatSaysNothingOfWhereItRuns() {
        XCTAssertTrue(chimesFinish(runningIn: nil, frontApp: "iTerm2", frontPath: "/Applications/iTerm.app"))
        XCTAssertTrue(chimesFinish(runningIn: DisplayHost(), frontApp: "iTerm2", frontPath: "/Applications/iTerm.app"))
    }
}
