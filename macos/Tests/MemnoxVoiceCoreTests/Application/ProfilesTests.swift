import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/profiles.test.ts.
final class ProfilesTests: XCTestCase {
    private static let backend = #"[{"id":"backend-engineering","name":"Backend Engineering","skills":["release-notes"],"mcpServers":["postgres"],"updatedAt":"2026-10-30T10:00:00Z","missing":[]}]"#

    func testReadsKeepsAppliesAndForgetsRedrawingFromEveryAnswer() async throws {
        let link = ScriptedLink()
        link.answers["profiles"] = [try line(#"{"id":1,"ok":true,"profiles":"# + Self.backend + "}")]
        link.answers["profile-put"] = [try line(#"{"id":2,"ok":true,"profiles":"# + Self.backend + "}")]
        link.answers["profile-apply"] = [try line(#"{"id":3,"ok":true,"profiles":"# + Self.backend + #","profileApplied":{"profile":"Backend Engineering","agent":"claude-code","proposed":["p1"],"already":[],"skipped":[]}}"#)]
        link.answers["profile-remove"] = [try line(#"{"id":4,"ok":true,"profiles":[]}"#)]
        let profiles = Profiles(link: link)
        await profiles.refresh()
        XCTAssertEqual(profiles.profiles?.first?.name, "Backend Engineering")
        let kept = await profiles.put(ProfileDraft(name: "Backend Engineering"))
        XCTAssertEqual(kept, .done("Backend Engineering is kept. It gives nothing until you apply it."))
        let applied = await profiles.apply("backend-engineering", agent: "claude-code", project: " /code/api ")
        XCTAssertEqual(applied, .done("1 proposal waits for your signature with Touch ID on the island."))
        let apply = try XCTUnwrap(link.sent.first { $0.method == "profile-apply" })
        XCTAssertEqual(apply.profileName, "backend-engineering")
        XCTAssertEqual(apply.profileAgent, "claude-code")
        XCTAssertEqual(apply.profileProject, "/code/api")
        let removed = await profiles.remove("backend-engineering")
        // Pressed by id, said by name, since the person reads names.
        XCTAssertEqual(removed, .done("Backend Engineering is forgotten. What it already gave stays where it was given."))
        XCTAssertEqual(profiles.profiles, [])
    }

    func testSavesAnEditUnderTheSameNameAndSaysItGrantsNothing() async throws {
        let link = ScriptedLink()
        link.answers["profile-put"] = [try line(#"{"id":1,"ok":true,"profiles":"# + Self.backend + "}")]
        let saved = await Profiles(link: link).put(ProfileDraft(name: "Backend Engineering", skills: ["release-notes"]), editing: true)
        XCTAssertEqual(saved, .done("Backend Engineering is saved. What it already gave stays, and the change gives nothing until you apply it again."))
        XCTAssertEqual(link.sent.first?.profileDraft, ProfileDraft(name: "Backend Engineering", skills: ["release-notes"]))
    }

    func testLeavesTheProjectOutForTheHomeFolderAndSaysARefusal() async throws {
        let link = ScriptedLink()
        link.answers["profile-apply"] = [try line(#"{"id":1,"ok":false,"error":"No profile is called nope."}"#)]
        let refused = await Profiles(link: link).apply("nope", agent: "codex-cli", project: "")
        XCTAssertEqual(refused, .failed("No profile is called nope."))
        XCTAssertNil(link.sent.first?.profileProject)
    }

    func testLaunchesWithAProfileAndSaysBothInOneLine() async throws {
        let link = ScriptedLink()
        link.answers["agent-launch"] = [try line(#"{"id":1,"ok":true,"proposed":"p1","agentLaunched":{"agent":"claude-code","workingDirectory":"/code/api","line":"claude"},"profileApplied":{"profile":"Backend","agent":"claude-code","proposed":["p1","p2"],"already":[],"skipped":[]}}"#)]
        let agents = Agents(link: link)
        let outcome = await agents.launch("claude-code", in: "/code/api", profile: "Backend")
        XCTAssertEqual(link.sent.first?.profileName, "Backend")
        XCTAssertEqual(outcome, .done("Opened claude-code in /code/api, typing claude. 2 proposals wait for your signature with Touch ID on the island."))
    }

    func testRemovesAPersonalSkillFromEveryAgentAtOnce() async throws {
        let link = ScriptedLink()
        link.answers["skill-remove"] = [try line(#"{"id":1,"ok":true,"skillsHub":{"skills":[],"found":[],"agents":[]}}"#)]
        let hub = SkillsHub(link: link)
        let removed = await hub.remove("release-notes")
        XCTAssertEqual(removed, .done("release-notes was taken out of the hub and every agent, its kept versions with it."))
        XCTAssertEqual(link.sent.first?.skillName, "release-notes")
        XCTAssertEqual(hub.hub?.skills, [])
    }
}

/// Jobs as the profile editor steers them: binding and copying a template are unsigned, and a template applies no rule.
final class ProfileJobsTests: XCTestCase {
    private static let job = #"[{"id":"backend","name":"Backend","skills":[],"mcpServers":[],"updatedAt":"2026-11-07T10:00:00Z","missing":[],"purpose":"Builds the API"}]"#

    func testGivesAnAgentsDefaultAJobInOnePress() async throws {
        let link = ScriptedLink()
        link.answers["profile-put"] = [try line(#"{"id":1,"ok":true,"profiles":"# + Self.job + "}")]
        link.answers["profile-bind"] = [try line(#"{"id":2,"ok":true,"profiles":"# + Self.job + "}")]
        let outcome = await Profiles(link: link).putAndBind(ProfileDraft(name: "Backend", purpose: "Builds the API"), agent: "agt_claude-code")
        XCTAssertEqual(outcome, .done("The agent now works under Backend."))
        XCTAssertEqual(link.sent.map(\.method), ["profile-put", "profile-bind"])
        XCTAssertEqual(link.sent.last?.agentId, "agt_claude-code")
        XCTAssertEqual(link.sent.last?.profileName, "Backend")
        XCTAssertNil(link.sent.last?.signature)
    }

    func testStopsBeforeBindingWhenTheJobWasRefused() async throws {
        let link = ScriptedLink()
        link.answers["profile-put"] = [try line(#"{"id":1,"ok":false,"error":"Give the profile a name."}"#)]
        let outcome = await Profiles(link: link).putAndBind(ProfileDraft(name: ""), agent: "claude-code")
        XCTAssertEqual(outcome, .failed("Give the profile a name."))
        XCTAssertEqual(link.sent.map(\.method), ["profile-put"])
    }

    func testCopiesATemplateWithOnlyTheSkillsTakenAndUnbinds() async throws {
        let link = ScriptedLink()
        link.answers["templates"] = [try line(#"{"id":1,"ok":true,"templates":[{"id":"code-review","name":"Code Review","purpose":"Reads a change","role":"reviewer","responsibilities":[],"suggestedSkills":["review"],"suggestedRules":["Never push."],"suggestedConnections":[]}]}"#)]
        link.answers["profile-from-template"] = [try line(#"{"id":2,"ok":true,"profiles":"# + Self.job + "}")]
        link.answers["profile-unbind"] = [try line(#"{"id":3,"ok":true,"profiles":[]}"#)]
        let profiles = Profiles(link: link)
        await profiles.readTemplates()
        XCTAssertEqual(profiles.templates?.first?.suggestedRules, ["Never push."])
        let copied = await profiles.fromTemplate("code-review", named: "Reviewer", skills: [])
        XCTAssertEqual(copied, .done("Reviewer is kept with no agent behind it yet. Its suggested rules wait for you to write them."))
        let copy = try XCTUnwrap(link.sent.first { $0.method == "profile-from-template" })
        XCTAssertEqual(copy.templateId, "code-review")
        XCTAssertEqual(copy.profileName, "Reviewer")
        XCTAssertEqual(copy.templateSkills, [])
        _ = await profiles.unbind(agent: "agt_codex-cli", from: "backend")
        XCTAssertEqual(link.sent.last?.agentId, "agt_codex-cli")
        XCTAssertEqual(profiles.profiles, [])
    }

    func testKeepsAJobWithOnlyItsPurposeAndCarriesItsFieldsThroughAnEdit() throws {
        let form = ProfileForm(name: "Backend", purpose: " Builds the API ", responsibilities: "run the tests\n\n keep the fingerprint ",
                               responsiblePerson: "Bo", projects: ["/code/api"], templateOf: "software-development")
        let draft = try ProfileLines.draft(form, packs: []).get()
        XCTAssertEqual(draft.purpose, "Builds the API")
        XCTAssertEqual(draft.responsibilities, ["run the tests", "keep the fingerprint"])
        XCTAssertEqual(draft.projects, ["/code/api"])
        XCTAssertEqual(draft.templateOf, "software-development")
        XCTAssertNil(draft.role)
        let kept = ProfileView(id: "backend", name: "Backend", updatedAt: "", purpose: "Builds the API", responsibilities: ["a", "b"],
                               projects: ["/code/api"])
        XCTAssertEqual(ProfileLines.form(of: kept, packs: []).responsibilities, "a\nb")
        XCTAssertEqual(ProfileLines.form(of: kept, packs: []).projects, ["/code/api"])
    }
}
