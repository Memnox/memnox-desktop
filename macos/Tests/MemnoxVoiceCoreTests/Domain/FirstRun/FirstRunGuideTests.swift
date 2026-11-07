import XCTest

@testable import MemnoxVoiceCore

final class FirstRunGuideTests: XCTestCase {
    /// Long enough for one idea said aloud, short enough that nobody waits on the voice to press on.
    private static let longestSpokenLine = 160

    private var everyLine: [String] {
        FirstRunPage.allCases.flatMap(FirstRunGuide.lines)
            + [FirstRunGuide.askName, FirstRunGuide.welcome(name: "Sam"), FirstRunGuide.packProposed, FirstRunGuide.imported(3)]
            + FirstRunGuide.scanned(ScanTally(findings: []))
            + [FirstRunEnd.permissionHint(hearing: false) ?? ""]
    }

    func testTellsThePersonOnlyToPressOnOrGrantAPermission() {
        let said = everyLine.joined(separator: " ")
        for chore in ["Terminal", "run memnox", "install Kokoro", "download"] {
            XCTAssertFalse(said.contains(chore), "the guide asks the person to \(chore)")
        }
    }

    func testSaysSomethingOnEveryPageFromTheFirstStepToTheLast() {
        for page in FirstRunPage.allCases {
            XCTAssertFalse(FirstRunGuide.lines(page).isEmpty, "page \(page) says nothing")
        }
    }

    func testNamesEveryFeatureOnTheWay() {
        let said = everyLine.joined(separator: " ")
        for feature in ["connectors", "allow, ask or deny", "Touch ID", "island", "microphone", "skills and tools",
                        "only on this Mac", "activity record", "iPhone", "installs and starts by itself"] {
            XCTAssertTrue(said.contains(feature), "the guide never says \(feature)")
        }
    }

    func testKeepsEveryLineShortAndFreeOfDashes() {
        for line in everyLine {
            XCTAssertLessThanOrEqual(line.count, Self.longestSpokenLine, line)
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }

    func testGreetsByNameOnlyWhenOneWasGiven() {
        XCTAssertTrue(FirstRunGuide.welcome(name: " Sam ").hasPrefix("Hi Sam, I'm Memnox."))
        XCTAssertTrue(FirstRunGuide.welcome(name: "").hasPrefix("Hi, I'm Memnox."))
    }

    func testSaysWhatTheSecondStepFoundOrThatThereIsNothing() {
        let found = FoundToImport(servers: [.init(agent: "cursor", name: "notion")], skills: [], agents: 1)
        XCTAssertTrue(FirstRunGuide.found(found).hasPrefix("We found 1 tool and 0 skills across 1 agent. I ticked every one."))
        XCTAssertTrue(FirstRunGuide.found(FoundToImport(servers: [], skills: [], agents: 0)).contains("nothing to bring in"))
        XCTAssertEqual(FirstRunGuide.imported(1), "Done. 1 item is now kept once in Memnox, and shared with the agents you choose. Press Continue.")
    }
}
