import XCTest

@testable import MemnoxVoiceCore

final class RuleTomlTests: XCTestCase {
    func testWritesARuleInTheRuntimesTableShape() {
        let table = RuleTable(name: "no-history-rewrites", match: RuleMatchTable(actions: ["git.push-force"], agents: ["claude-code"]),
                              effect: "deny", reason: "it rewrites history",
                              alternative: RuleAlternative(action: "git.push", note: "Push a branch."))
        XCTAssertEqual(RuleToml.text(table), """
        [[policies]]
        name = "no-history-rewrites"

        [policies.match]
        actions = [ "git.push-force" ]
        agents = [ "claude-code" ]

        [policies.decision]
        effect = "deny"
        reason = "it rewrites history"

        [policies.decision.alternative]
        action = "git.push"
        note = "Push a branch."
        """)
    }

    func testWritesArgumentsInTheirOwnTableAndEscapesQuotes() {
        let table = RuleTable(name: "http", match: RuleMatchTable(actions: ["http.request"], arguments: [RuleArgument("method", ["POST"])]),
                              effect: "ask", reason: "a \"change\"")
        let text = RuleToml.text(table)
        XCTAssertTrue(text.contains("[policies.match.arguments]\nmethod = [ \"POST\" ]"))
        XCTAssertTrue(text.contains("reason = \"a \\\"change\\\"\""))
    }

    func testWritesADraftWithItsDataAndAPlaceholderUntilAnActionIsNamed() {
        let empty = RuleToml.table(of: RuleDraftInput(effect: .ask, action: "", reason: "why"), dataClassifications: nil)
        XCTAssertEqual(empty.name, "rule-ask")
        XCTAssertEqual(empty.match.actions, [RuleToml.actionPlaceholder])
        let draft = RuleDraftInput(effect: .deny, action: "Vercel.deploy-prod", targets: ["!api.stripe.com"], reason: "why")
        let table = RuleToml.table(of: draft, dataClassifications: ["secret"])
        XCTAssertEqual(table.name, "vercel-deploy-prod-deny")
        XCTAssertTrue(RuleToml.text(table).contains("targets = [ \"!api.stripe.com\" ]\ndataClassifications = [ \"secret\" ]"))
    }

    func testTogglesAWordInACommaSeparatedField() {
        XCTAssertEqual(RuleToml.toggled("secret", in: ""), "secret")
        XCTAssertEqual(RuleToml.toggled("health", in: "secret, codename"), "secret, codename, health")
        XCTAssertEqual(RuleToml.toggled("secret", in: "secret, codename"), "codename")
        XCTAssertNil(RuleToml.words(" , "))
    }

    func testOpensADocumentWithTheVersionLine() {
        XCTAssertEqual(RuleToml.document(["a", "b"]), "version = 1\n\na\n\nb")
    }
}
