import XCTest

@testable import MemnoxVoiceCore

final class ReadyRuleChangesTests: XCTestCase {
    private let history = ReadyRules.rule(ReadyRuleLibrary.rules[0])
    private let deleting = ReadyRules.starter[1]

    private func held(_ rule: ReadyRule, _ effect: String, editable: Bool = true) -> PolicyRuleView {
        PolicyRuleView(name: rule.id, effect: effect, match: PolicyRuleMatch(actions: rule.actions), sentence: "",
                       source: editable ? "person" : "file", editable: editable)
    }

    func testSaysTheEffectInForceOrNotAddedOnTheBadge() {
        let inForce = [held(history, "deny")]
        XCTAssertEqual(ReadyRuleChanges.badge(history, among: inForce).word, "In force as deny")
        XCTAssertEqual(ReadyRuleChanges.badge(history, among: inForce).tone, .bad)
        XCTAssertEqual(ReadyRuleChanges.badge(deleting, among: inForce).word, "Not added")
        XCTAssertEqual(ReadyRuleChanges.badge(deleting, among: inForce).tone, .quiet)
    }

    func testGathersOnlyPicksThatChangeWhatHolds() {
        let inForce = [held(history, "deny")]
        let changes = ReadyRuleChanges.changes([history.id: .deny, deleting.id: .ask], rules: [history, deleting], among: inForce)
        XCTAssertEqual(changes, [ReadyRuleChange(rule: deleting, from: nil, to: .ask)])
        let moved = ReadyRuleChanges.changes([history.id: .ask], rules: [history], among: inForce)
        XCTAssertEqual(moved.map(ReadyRuleChanges.changeLine), ["Deny to Ask"])
        XCTAssertEqual(ReadyRuleChanges.removals(moved), [history.id])
    }

    func testLeavesARuleFromAFileToWhereItCameFrom() {
        let inForce = [held(history, "deny", editable: false)]
        XCTAssertFalse(ReadyRuleChanges.canChange(history, among: inForce))
        XCTAssertEqual(ReadyRuleChanges.changes([history.id: .ask], rules: [history], among: inForce), [])
        XCTAssertTrue(ReadyRuleChanges.canChange(deleting, among: inForce))
    }

    func testPicksTheSuggestedEffectForEveryRuleNotAddedYet() {
        let inForce = [held(history, "deny")]
        let picked = ReadyRuleChanges.picking([history, deleting], into: [:], among: inForce)
        XCTAssertEqual(picked, [deleting.id: deleting.effect])
        // A pick the person already made is kept rather than reset.
        XCTAssertEqual(ReadyRuleChanges.picking([deleting], into: [deleting.id: .deny], among: []), [deleting.id: .deny])
    }

    func testCountsTheChangesAndWhatTheSearchLeaves() {
        XCTAssertEqual(ReadyRuleChanges.countLine(1), "1 change")
        XCTAssertEqual(ReadyRuleChanges.countLine(3), "3 changes")
        XCTAssertEqual(ReadyRuleChanges.shownLine(12, of: 48), "12 of 48")
        XCTAssertEqual(ReadyRuleChanges.changeLine(ReadyRuleChange(rule: deleting, from: nil, to: .allow)), "Not added to Allow")
    }

    func testWritesAnAllowLikeAnyOtherEffectWithNoWayRound() {
        let toml = ReadyRuleChanges.toml([ReadyRuleChange(rule: history, from: nil, to: .allow)]) ?? ""
        XCTAssertTrue(toml.contains("effect = \"allow\""))
        XCTAssertFalse(toml.contains("[policies.decision.alternative]"))
        XCTAssertNil(ReadyRuleChanges.toml([]))
    }

    func testListsEachRuleOnceAcrossGroups() {
        let groups = [ReadyRuleGroup(id: "a", title: "A", rules: [history, deleting]),
                      ReadyRuleGroup(id: "b", title: "B", rules: [history])]
        XCTAssertEqual(ReadyRuleChanges.flat(groups).map(\.id), [history.id, deleting.id])
    }
}
