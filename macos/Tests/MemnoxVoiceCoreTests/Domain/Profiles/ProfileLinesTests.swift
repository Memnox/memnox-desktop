import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the wording half of shared/tauri-core/test/profiles.test.ts, with Touch ID for the key.
final class ProfileLinesTests: XCTestCase {
    private let packs = [RulePackView(id: "careful", name: "Careful", description: "d", ruleCount: 6, toml: "[[policies]]")]

    func testCountsWhatItBundlesNeverAScore() {
        let backend = ProfileView(id: "backend-engineering", name: "Backend Engineering", skills: ["review-checklist", "release-notes"],
                                  mcpServers: ["postgres"], rulePack: ProfilePackSummary(name: "Careful", rules: 6), updatedAt: "2026-10-30T10:00:00Z")
        XCTAssertEqual(ProfileLines.contents(backend), "2 skills · 1 server · Careful, 6 rules")
        XCTAssertEqual(ProfileLines.contents(ProfileView(id: "a", name: "a", skills: ["a"], updatedAt: "")), "1 skill · 0 servers · No rule pack")
    }

    func testSaysWhatAnApplyRaisedWhatWasAlreadyGivenAndWhatWasSkipped() {
        XCTAssertEqual(ProfileLines.applied(ProfileApplied(profile: "p", agent: "a", proposed: ["p1", "p2"], already: ["postgres"]), keyTitle: "Touch ID"),
                       "2 proposals wait for your signature with Touch ID on the island. 1 was already given.")
        XCTAssertEqual(ProfileLines.applied(ProfileApplied(profile: "p", agent: "a", skipped: ["figma is not in the MCP Hub."]), keyTitle: "Touch ID"),
                       "Skipped: figma is not in the MCP Hub.")
        XCTAssertEqual(ProfileLines.applied(ProfileApplied(profile: "p", agent: "a"), keyTitle: "Touch ID"), "The profile holds nothing to give.")
    }

    func testOpensAnEditWithTheProfileAsKeptAndItsPackMatchedByName() {
        let backend = ProfileView(id: "backend", name: "Backend", skills: ["a"], mcpServers: ["postgres"],
                                  rulePack: ProfilePackSummary(name: "Careful", rules: 6), updatedAt: "")
        XCTAssertEqual(ProfileLines.form(of: backend, packs: packs), ProfileForm(name: "Backend", skills: ["a"], servers: ["postgres"], pack: "careful"))
        XCTAssertEqual(ProfileLines.form(of: backend, packs: []).pack, "")
    }

    func testKeepsANameTheHubNoLongerHoldsTickableAfterWhatItHolds() {
        XCTAssertEqual(ProfileLines.choiceNames(["a", "b"], kept: ["b", "z", "gone"]), ["a", "b", "gone", "z"])
    }

    func testSaysWhatSavingDoesToThePackTheProfileKeeps() {
        let kept = ProfilePackSummary(name: "Careful", rules: 6)
        XCTAssertNil(ProfileLines.packChange(kept: nil, form: ProfileForm(), packs: packs))
        XCTAssertNil(ProfileLines.packChange(kept: kept, form: ProfileForm(pack: "careful"), packs: packs))
        XCTAssertEqual(ProfileLines.packChange(kept: kept, form: ProfileForm(), packs: packs), "Saving takes Careful out of the profile.")
        XCTAssertEqual(ProfileLines.packChange(kept: kept, form: ProfileForm(), packs: []),
                       "Careful is no longer offered here, so saving takes it out of the profile. Choose a pack to keep one.")
        let open = RulePackView(id: "open", name: "Open", description: "d", ruleCount: 2, toml: "")
        XCTAssertEqual(ProfileLines.packChange(kept: kept, form: ProfileForm(pack: "open"), packs: packs + [open]), "Saving replaces Careful with Open.")
        let grown = [RulePackView(id: "careful", name: "Careful", description: "d", ruleCount: 7, toml: "")]
        XCTAssertEqual(ProfileLines.packChange(kept: kept, form: ProfileForm(pack: "careful"), packs: grown),
                       "Saving takes Careful as it is offered now, 7 rules where the profile keeps 6.")
    }

    func testSaysWhereSkillsGoBeforeApply() {
        XCTAssertEqual(ProfileLines.applyWhere(" "), "Skills go into the agent’s home folder.")
        XCTAssertEqual(ProfileLines.applyWhere("/code/api"), "Skills go into /code/api.")
    }

    func testMakesTheDraftWithThePacksTextAndSortedLists() {
        let form = ProfileForm(name: " Backend ", skills: ["b", "a"], pack: "careful")
        XCTAssertEqual(try ProfileLines.draft(form, packs: packs).get(),
                       ProfileDraft(name: "Backend", skills: ["a", "b"], rulePack: ProfileRulePack(name: "Careful", toml: "[[policies]]")))
    }

    func testSaysWhatIsMissing() {
        let form = ProfileForm(name: "Backend", skills: ["a"], pack: "careful")
        XCTAssertEqual(problem(ProfileForm(name: "", skills: ["a"])), "Give the profile a name.")
        XCTAssertEqual(problem(ProfileForm(name: "Backend")), "Choose at least one skill, server or rule pack.")
        var gone = form
        gone.pack = "gone"
        XCTAssertEqual(problem(gone), "That rule pack is no longer offered. Choose another.")
    }

    private func problem(_ form: ProfileForm) -> String? {
        if case .failure(let problem) = ProfileLines.draft(form, packs: packs) { return problem.why }
        return nil
    }
}
