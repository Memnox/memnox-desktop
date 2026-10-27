import XCTest

@testable import MemnoxVoiceCore

final class FirstRunGuideTests: XCTestCase {
    /// Long enough for one idea said aloud, short enough that nobody waits on the voice to press on.
    private static let longestSpokenLine = 160

    private var everyLine: [String] {
        FirstRunPage.allCases.flatMap(FirstRunGuide.lines)
            + [FirstRunGuide.askName, FirstRunGuide.welcome(name: "Sam"), FirstRunGuide.packProposed, FirstRunGuide.imported(3)]
            + FirstRunGuide.scanned(ScanTally(findings: []))
    }

    func testSaysSomethingOnEveryPageFromTheFirstStepToTheLast() {
        for page in FirstRunPage.allCases {
            XCTAssertFalse(FirstRunGuide.lines(page).isEmpty, "page \(page) says nothing")
        }
    }

    func testNamesEveryFeatureOnTheWay() {
        let said = everyLine.joined(separator: " ")
        for feature in ["connectors", "allow, ask or deny", "Touch ID", "island", "Option Space", "skills and MCP servers",
                        "only on this Mac", "activity record", "iPhone"] {
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
        XCTAssertTrue(FirstRunGuide.found(found).hasPrefix("We found 1 MCP server and 0 skills across 1 agent."))
        XCTAssertTrue(FirstRunGuide.found(FoundToImport(servers: [], skills: [], agents: 0)).contains("nothing to bring in"))
        XCTAssertEqual(FirstRunGuide.imported(1), "Done. 1 item is now kept once in Memnox, and shared with the agents you choose. Press Continue.")
    }
}
