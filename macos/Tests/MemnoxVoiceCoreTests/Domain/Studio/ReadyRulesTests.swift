import XCTest

@testable import MemnoxVoiceCore

final class ReadyRulesTests: XCTestCase {
    private let toml = """
    # A rule pack.
    version = 1

    [pack]
    name = "Safe defaults"
    description = "Agents work freely."

    [[policies]]
    name = "pack-delete-ask"
    description = "Deleting files"

    [policies.match]
    actions = [ "filesystem.delete" ]

    [policies.decision]
    effect = "ask"
    reason = "a delete is sometimes the only copy"

    [[policies]]
    name = "pack-history-deny"
    description = "Force pushing and hard resets"

    [policies.match]
    actions = [ "git.push-force", "git.reset-hard" ]

    [policies.decision]
    effect = "deny"
    reason = "it rewrites history."
    """

    private var pack: RulePackView {
        RulePackView(id: "safe-defaults", name: "Safe defaults", description: "", ruleCount: 2, toml: toml)
    }

    func testReadsEachPackRuleWithItsOwnImportableText() {
        let rules = ReadyRules.rules(of: pack)
        XCTAssertEqual(rules.map(\.id), ["pack-delete-ask", "pack-history-deny"])
        XCTAssertEqual(rules.map(\.title), ["Deleting files", "Force pushing and hard resets"])
        XCTAssertEqual(rules.map(\.says), ["A delete is sometimes the only copy.", "It rewrites history."])
        XCTAssertEqual(rules[1].actions, ["git.push-force", "git.reset-hard"])
        XCTAssertEqual(rules.map(\.effect), [.ask, .deny])
        let text = ReadyRules.toml([(rules[1], .deny)])
        XCTAssertEqual(text?.contains("[pack]"), true)
        XCTAssertEqual(text?.contains("pack-history-deny"), true)
        XCTAssertEqual(text?.contains("pack-delete-ask"), false)
    }

    func testPutsTheLibraryFirstInCategoryOrderThenThePacks() {
        let groups = ReadyRules.groups([pack])
        XCTAssertEqual(groups.map(\.id), ReadyRuleCategory.allCases.map(\.rawValue) + ["safe-defaults"])
        XCTAssertEqual(groups.first?.title, "Code and git")
        XCTAssertEqual(groups.first?.rules.first?.marks, [.git])
    }

    func testDropsAPackRuleTheLibraryAlreadyOffers() {
        let doubled = RulePackView(id: "doubled", name: "Doubled", description: "", ruleCount: 1, toml: """
        version = 1

        [[policies]]
        name = "no-history-rewrites"

        [policies.match]
        actions = [ "git.push-force" ]

        [policies.decision]
        effect = "deny"
        """)
        XCTAssertFalse(ReadyRules.groups([doubled]).contains { $0.id == "doubled" })
    }

    func testNarrowsByGroupAndByEveryWordOfTheSearch() {
        let groups = ReadyRules.groups([pack])
        XCTAssertEqual(ReadyRules.shown(groups, group: "safe-defaults", query: "").map(\.id), ["safe-defaults"])
        XCTAssertEqual(ReadyRules.shown(groups, group: nil, query: "RESET pushing").flatMap(\.rules).map(\.id), ["pack-history-deny"])
        XCTAssertEqual(ReadyRules.shown(groups, group: nil, query: "kubectl.drain").flatMap(\.rules).map(\.id),
                       ["ask-before-kubernetes-deletes"])
        XCTAssertTrue(ReadyRules.shown(groups, group: nil, query: "nothing-matches-this").isEmpty)
    }

    func testRewritesOnlyTheDecisionsEffectOfAPackRule() {
        let delete = ReadyRules.rules(of: pack)[0]
        let table = ReadyRules.table(delete, effect: .deny)
        XCTAssertTrue(table.contains("effect = \"deny\""))
        XCTAssertFalse(table.contains("effect = \"ask\""))
        XCTAssertTrue(table.contains("name = \"pack-delete-ask\""))
    }

    func testWritesALibraryRuleWithWhoChoseItAndTheWayRoundOnlyWhenRefused() {
        guard let history = ReadyRuleLibrary.rules.first(where: { $0.id == "no-history-rewrites" }) else {
            return XCTFail("the library carries no-history-rewrites")
        }
        let denied = ReadyRules.libraryTable(history, effect: .deny)
        XCTAssertEqual(denied.reason, "you chose to deny this: it rewrites history somebody else may already have pulled")
        XCTAssertEqual(denied.alternative?.action, "git.push")
        let asked = ReadyRules.libraryTable(history, effect: .ask)
        XCTAssertEqual(asked.reason, "you chose to be asked about this: it rewrites history somebody else may already have pulled")
        XCTAssertNil(asked.alternative)
        let document = ReadyRules.toml([(ReadyRules.rule(history), .ask)])
        XCTAssertEqual(document?.hasPrefix(RuleToml.header), true)
        XCTAssertEqual(document?.contains("[policies.decision.alternative]"), false)
    }

    func testFindsTheRuleInForceByItsName() {
        let rules = [
            PolicyRuleView(name: "pack-history-deny", effect: "deny", match: PolicyRuleMatch(actions: ["git.push-force"]),
                           sentence: "", source: "person", editable: true),
        ]
        let packRules = ReadyRules.rules(of: pack)
        XCTAssertEqual(ReadyRules.inForce(packRules[1], among: rules)?.name, "pack-history-deny")
        XCTAssertNil(ReadyRules.inForce(packRules[0], among: rules))
    }

    func testOffersTheStarterSetInLibraryOrder() {
        XCTAssertEqual(ReadyRules.starter.map(\.id), [
            "no-history-rewrites", "ask-before-deleting-files", "ask-before-changing-production", "ask-before-moving-money",
            "keep-out-of-credentials", "ask-before-mcp-changes", "ask-before-http-changes",
        ])
    }
}
