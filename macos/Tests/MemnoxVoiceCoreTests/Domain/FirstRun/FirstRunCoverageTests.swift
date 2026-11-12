import XCTest

@testable import MemnoxVoiceCore

final class FirstRunCoverageTests: XCTestCase {
    private func levels(shell: CapabilityLevel, others: CapabilityLevel) -> CapabilityLevels {
        CapabilityLevels(context: others, instructions: others, tools: .mediated, activity: .observed, coordination: others,
                         approval: others, enforcement: ["shell": shell, "filesystem": shell, "git": shell])
    }

    func testGroupsWhatAnAgentDoesByLevelStrongestFirst() {
        let lines = FirstRunCoverage.lines(levels(shell: .enforced, others: .noEvidence))
        XCTAssertEqual(lines.map(\.level), [.enforced, .mediated, .observed, .noEvidence])
        XCTAssertEqual(lines.first?.sentence, "Memnox stops this: Commands, Files and Git.")
        XCTAssertEqual(lines[1].sentence, "Memnox checks this: Its tools.")
        XCTAssertEqual(lines.last?.plain, "Outside Memnox")
    }

    func testLeavesOutALevelNothingSitsAt() {
        let lines = FirstRunCoverage.lines(CapabilityLevels.outside)
        XCTAssertEqual(lines.map(\.level), [.noEvidence])
    }

    func testKeepsEveryWordFreeOfDashes() {
        let words = [FirstRunCoverage.nothingFound, FirstRunCoverage.title, FirstRunCoverage.lead, FirstRunCoverage.cannot,
                     FirstRunCoverage.showDetails, FirstRunCoverage.hideDetails]
        for line in words {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }
}
