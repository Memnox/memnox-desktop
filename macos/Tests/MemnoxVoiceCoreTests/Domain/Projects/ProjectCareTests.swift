import XCTest

@testable import MemnoxVoiceCore

/// How careful agents are in one project, read off the rules that hold there, and the examples shown before any exists.
final class ProjectCareTests: XCTestCase {
    private func rule(_ name: String) -> PolicyRuleView {
        PolicyRuleView(name: name, effect: "ask", match: PolicyRuleMatch(actions: ["*"]), sentence: name, source: "machine", editable: true)
    }

    func testIsRelaxedWithNoStarterRulesOfItsOwn() {
        XCTAssertEqual(ProjectCare.of(rulesHere: []), .relaxed)
        XCTAssertEqual(ProjectCare.of(rulesHere: [rule("my-own-rule")]), .relaxed)
        XCTAssertNil(ProjectCare.relaxed.level)
    }

    func testNamesTheStrictestPackStartedHere() {
        XCTAssertEqual(ProjectCare.of(rulesHere: [rule("pack-safe-defaults-delete-ask")]), .careful)
        XCTAssertEqual(ProjectCare.of(rulesHere: [rule("pack-safe-defaults-delete-ask"), rule("pack-read-only-agents-write-ask")]), .strict)
        XCTAssertEqual(ProjectCare.careful.level?.packId, "safe-defaults")
        XCTAssertEqual(ProjectCare.strict.level?.packId, "read-only-agents")
    }

    func testShowsThreeExamplesEachWithItsOwnCare() {
        XCTAssertEqual(ProjectExample.all.map(\.care), [.relaxed, .careful, .strict])
        XCTAssertEqual(ProjectWhy.lines.count, 4)
    }
}
