import XCTest

@testable import MemnoxVoiceCore

final class FirstRunQuestionsTests: XCTestCase {
    private func levels(shell: CapabilityLevel, others: CapabilityLevel) -> CapabilityLevels {
        CapabilityLevels(context: others, instructions: others, tools: .mediated, activity: .observed, coordination: others,
                         approval: others, enforcement: ["shell": shell, "filesystem": shell, "git": shell])
    }

    func testOffersTheSixCategoriesAndNoneYet() {
        XCTAssertEqual(AgentPlace.allCases.count, 7)
        XCTAssertEqual(AgentPlace.allCases.filter(\.isLocal), [.thisMacCoding, .thisMacApp])
        XCTAssertEqual(AgentPlace.allCases.filter(\.throughCloud), [.hosted, .insideApp, .noCode, .ownCode])
        XCTAssertFalse(AgentPlace.noneYet.throughCloud)
    }

    func testSuggestsThisMacOnlyWhenTheScanFoundAgentsHere() {
        XCTAssertEqual(AgentPlace.suggested(foundHere: 2), .thisMacCoding)
        XCTAssertNil(AgentPlace.suggested(foundHere: 0))
    }

    func testNeverClaimsALevelForThisMacOrForNoAgent() {
        // The service states this Mac's levels itself, and nothing does a job with no agent.
        XCTAssertNil(AgentPlace.thisMacCoding.expected)
        XCTAssertNil(AgentPlace.thisMacApp.expected)
        XCTAssertNil(AgentPlace.noneYet.expected)
        // No connection kind reached through Memnox Cloud is ever said to be stopped without a proof.
        for place in AgentPlace.allCases { XCTAssertNotEqual(place.expected, .enforced) }
        XCTAssertEqual(AgentPlace.insideApp.expected, .advisory)
        XCTAssertEqual(AgentPlace.hosted.expected, .mediated)
    }

    func testSaysARemoteAgentIsOutsideUntilItIsConnected() {
        XCTAssertEqual(FirstRunCoverage.place(.insideApp),
                       "Outside Memnox until it is connected. Connected this way, expect: The agent asks Memnox.")
        XCTAssertEqual(FirstRunCoverage.place(.noneYet), AgentPlace.noneYet.connects)
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
        let words = AgentPlace.allCases.flatMap { [$0.title, $0.detail, $0.connects, FirstRunCoverage.place($0)] }
            + [FirstRunQuestions.placeTitle, FirstRunQuestions.placeDetail, FirstRunQuestions.cloudOptional, FirstRunQuestions.nothingFound, FirstRunCoverage.title,
               FirstRunCoverage.lead, FirstRunCoverage.cannot]
        for line in words {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }
}
