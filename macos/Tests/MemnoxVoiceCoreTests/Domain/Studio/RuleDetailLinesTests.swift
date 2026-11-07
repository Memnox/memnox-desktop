import XCTest

@testable import MemnoxVoiceCore

final class RuleDetailLinesTests: XCTestCase {
    func testSaysAnActionTheWayAPersonWould() {
        XCTAssertEqual(RuleDetailLines.phrase("git.push-force"), "Git push force")
        XCTAssertEqual(RuleDetailLines.phrase("filesystem.delete"), "Delete a file")
        XCTAssertEqual(RuleDetailLines.phrase("mcp.issue_create"), "Create issue")
        XCTAssertEqual(RuleDetailLines.phrase("git.unknown"), "A git command Memnox does not recognise")
        XCTAssertEqual(RuleDetailLines.phrase("https://example.com"), "Automated action")
    }

    func testSaysTheRuleAsOneSentence() {
        let refused = RuleDetailLines.sentence(agents: nil, actions: ["git.push-force", "git.reset-hard"], targets: nil,
                                               effect: .deny) { $0 }
        XCTAssertEqual(refused, "When any agent tries to git push force, git reset hard, it is refused and told what to do instead.")
        let asked = RuleDetailLines.sentence(agents: ["codex"], actions: ["http.request"], targets: ["api.stripe.com"],
                                             effect: .ask) { $0.uppercased() }
        XCTAssertEqual(asked, "When CODEX tries to http request on api.stripe.com, it waits for a person to say yes.")
    }
}
