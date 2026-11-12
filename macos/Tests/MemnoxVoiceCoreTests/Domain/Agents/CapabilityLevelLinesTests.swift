import XCTest
@testable import MemnoxVoiceCore

/// The five levels in plain words, and a pill that never says more than the strip under it.
final class CapabilityLevelLinesTests: XCTestCase {
    private func levels(general: CapabilityLevel, tools: CapabilityLevel = .mediated, approval: CapabilityLevel = .enforced,
                        seams: [String: CapabilityLevel] = ["shell": .enforced, "git": .noEvidence]) -> CapabilityLevels {
        CapabilityLevels(context: general, instructions: general, tools: tools, activity: general, coordination: general,
                         approval: approval, enforcement: seams)
    }

    func testWordsEveryLevelPlainly() {
        XCTAssertEqual(CapabilityLevel.allCases.map(CapabilityLevelLines.plain),
                       ["Memnox stops this", "Memnox checks this", "The agent asks Memnox", "Memnox only sees this", "Outside Memnox"])
        XCTAssertEqual(CapabilityLevelLines.technical(.noEvidence), "none")
    }

    func testAPillWearsTheWeakestOfTheSixSoItNeverSaysMoreThanTheStrip() {
        XCTAssertEqual(CapabilityLevelLines.headline(levels(general: .mediated)), .mediated)
        XCTAssertEqual(CapabilityLevelLines.headline(levels(general: .advisory, approval: .advisory)), .advisory)
        XCTAssertEqual(CapabilityLevelLines.headline(levels(general: .mediated, tools: .observed)), .observed)
    }

    func testAnAdvisoryConnectionNeverReadsAsEnforced() {
        let connection = AgentConnection(id: "con_x", profileId: "p", kind: "mcp", mediation: "advisory", firstSeen: "", lastSeen: "",
                                         status: "live")
        XCTAssertEqual(CapabilityLevelLines.headline(connection), .advisory)
        XCTAssertEqual(CapabilityLevelLines.connectionKind(connection), "It talks to Memnox over MCP")
    }

    func testListsSeamsInTheRuntimesOrderThenOnesItDoesNotKnow() {
        let rows = CapabilityLevelLines.seamRows(levels(general: .mediated, seams: ["git": .noEvidence, "shell": .enforced, "docker": .observed]))
        XCTAssertEqual(rows.map(\.title), ["Commands", "Git", "docker"])
        XCTAssertEqual(rows.first?.technical, "enforcement.shell: enforced")
        XCTAssertEqual(CapabilityLevelLines.rows(.outside).map(\.plain), Array(repeating: "Outside Memnox", count: 6))
    }
}
