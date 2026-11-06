import XCTest

@testable import MemnoxVoiceCore

final class ReadyRuleLibraryTests: XCTestCase {
    func testCarriesEveryConsoleRuleOnceUnderItsOwnName() {
        let ids = ReadyRuleLibrary.rules.map(\.id)
        XCTAssertEqual(ids.count, 38)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ReadyRuleLibrary.starterSet.allSatisfy(ids.contains))
    }

    func testSuggestsOnlyEffectsThatHoldSomethingAndAWayRoundOnlyBesideAnAction() {
        XCTAssertEqual(ReadyRules.effects, [.allow, .ask, .deny])
        for rule in ReadyRuleLibrary.rules {
            XCTAssertNotEqual(rule.recommended, .allow, rule.id)
            XCTAssertFalse(rule.match.actions.isEmpty, rule.id)
            XCTAssertFalse(rule.marks.isEmpty, rule.id)
        }
    }

    func testDrawsAProductWithItsComposioLogoAndAKindOfActAsAGlyph() {
        XCTAssertEqual(RuleMark.github.toolkit, "github")
        XCTAssertEqual(RuleMark.docker.toolkit, "docker_hub")
        XCTAssertEqual(RuleMark.postgresql.toolkit, "postgres")
        XCTAssertNil(RuleMark.git.toolkit)
        XCTAssertNil(RuleMark.kubernetes.toolkit)
    }

    func testWritesTheProductionRuleWithItsEnvironmentsAndClasses() {
        guard let production = ReadyRuleLibrary.rules.first(where: { $0.id == "ask-before-changing-production" }) else {
            return XCTFail("the library carries ask-before-changing-production")
        }
        let text = RuleToml.text(ReadyRules.libraryTable(production, effect: .ask))
        XCTAssertTrue(text.contains("environments = [ \"prod*\", \"production\", \"live\" ]"))
        XCTAssertTrue(text.contains("classes = [ \"write\", \"destructive\", \"communication\" ]"))
        XCTAssertTrue(text.contains("\"!git.*\""))
    }
}
