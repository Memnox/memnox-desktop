import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the words tests in shared/tauri-core/test/studio.test.ts.
final class StudioLinesTests: XCTestCase {
    private let rules = [
        PolicyRuleView(name: "git-deny", effect: "deny", match: PolicyRuleMatch(actions: ["git.push-force"]), sentence: "Deny force pushes",
                       source: "file", file: "memnox.policies.toml", editable: false),
        PolicyRuleView(name: "mine", effect: "ask", match: PolicyRuleMatch(actions: ["filesystem.delete"]), sentence: "Ask before deleting",
                       source: "person", editable: true),
    ]

    func testCountsRulesPerEffectAndSaysWhereEachCameFrom() {
        XCTAssertEqual(StudioLines.countsByEffect(rules), [.allow: 0, .ask: 1, .deny: 1])
        XCTAssertEqual(StudioLines.sourceWords("workspace"), "From your team")
        XCTAssertEqual(StudioLines.sourceWords("person", decidedBy: "Sam"), "Set by Sam")
        XCTAssertEqual(StudioLines.sourceWords(rules[0]), "From memnox.policies.toml")
        XCTAssertEqual(StudioLines.sourceWords("person"), "Set on this computer")
        XCTAssertEqual(StudioLines.sourceWords("somewhere"), "somewhere")
    }

    func testSaysTheWeekInCountsAndHowCloseAHabitIsToBeingLetGo() {
        let now = ProgressWeek(from: "", asked: 12, answeredByAutopilot: 0, handedOver: 0)
        let then = ProgressWeek(from: "", asked: 1, answeredByAutopilot: 0, handedOver: 0)
        XCTAssertEqual(StudioLines.weekLine(thisWeek: now, lastWeek: then), "Asked you 12 times this week, 1 time last week.")
        XCTAssertEqual(StudioLines.almostLine(ProgressAlmost(action: "git.push", approvals: 4, needed: 5)),
                       "1 more yes to git.push and it is ready to let go")
        XCTAssertEqual(StudioLines.almostLine(ProgressAlmost(action: "git.push", approvals: 1, needed: 5)),
                       "4 more yeses to git.push and it is ready to let go")
        XCTAssertEqual(StudioLines.exportedCount("[[policies]]\nname = \"a\"\n[[policies]]\n"), 2)
        XCTAssertEqual(StudioLines.autopilotLine(0), "The autopilot answered nothing for you this week.")
        XCTAssertEqual(StudioLines.autopilotLine(1), "The autopilot answered 1 ask for you this week.")
    }

    func testReadsBackWhatARuleBeingBuiltWillDoBeforeAnythingIsProposed() {
        let push = RuleDraftInput(effect: .ask, action: "git.push", branches: ["main"], agents: ["codex-cli"], reason: "")
        XCTAssertEqual(StudioLines.draftSentence(push) { _ in "Codex" }, "Ask you before Codex runs git.push on the main branch.")
        XCTAssertEqual(StudioLines.draftSentence(RuleDraftInput(effect: .deny, action: "", reason: "")) { $0 },
                       "Never let any agent run this action.")
        XCTAssertEqual(StudioLines.draftSentence(RuleDraftInput(effect: .allow, action: "git.commit", targets: ["origin"],
                                                                workingDirectories: ["~/code"], reason: "")) { $0 },
                       "Let any agent run git.commit on origin in ~/code without asking.")
    }

    func testShowsASwitchOnOnlyWhenARuleAlreadyAsksAboutIt() {
        let ask = PolicyRuleView(name: "a", effect: "ask", match: PolicyRuleMatch(actions: ["git.push"], branches: ["main"]), sentence: "",
                                 source: "person", editable: true)
        let allow = PolicyRuleView(name: "b", effect: "allow", match: PolicyRuleMatch(actions: ["git.push"]), sentence: "",
                                   source: "person", editable: true)
        XCTAssertTrue(StudioLines.switchOn([ask], action: "git.push", branches: ["main"]))
        XCTAssertFalse(StudioLines.switchOn([allow], action: "git.push"))
        XCTAssertFalse(StudioLines.switchOn([ask], action: "git.push", branches: ["release"]))
        XCTAssertEqual(StudioLines.alwaysAsk.map(\.id), ["push-main", "delete-files", "mcp-writes"])
        XCTAssertEqual(StudioLines.alwaysAsk[2].draft.classes, ["write", "destructive", "communication"])
    }

    func testSaysEachEffectOnceAndWhoAnsweredARow() {
        XCTAssertEqual(StudioLines.words(.deny).says, "Refused, and told what to do instead")
        XCTAssertEqual(StudioLines.title("redact"), "redact")
        XCTAssertEqual(StudioLines.tone("ask"), .attention)
        XCTAssertEqual(StudioLines.activityLine(operation: "git.push", target: "origin"), "git.push origin")
        XCTAssertEqual(StudioLines.answeredWords(by: "Sam", how: "signed"), "Sam, signed")
        XCTAssertEqual(StudioLines.answeredWords(by: "Sam", how: "within-session"), "Sam, inside its session")
        XCTAssertNil(StudioLines.answeredWords(by: nil, how: "signed"))
    }

    func testPutsTheAgentsNeedingADecisionFirst() throws {
        let json = #"[{"kind":"d","name":"D","status":"dormant"},{"kind":"p","name":"P","status":"protected"},{"kind":"u","name":"U","status":"unprotected"},{"kind":"z","name":"Z","status":"paused"},{"kind":"p2","name":"P2","status":"protected"}]"#
        let filled = json.replacingOccurrences(of: #""}"#, with: #"","sessions":{"running":1,"idle":2,"finished":4},"mcpServers":[],"today":{"actions":3,"asked":1,"refused":0},"recent":[]}"#)
        let agents = try JSONDecoder().decode([AgentStanding].self, from: Data(filled.utf8))
        XCTAssertEqual(StudioLines.sortedAgents(agents).map(\.kind), ["z", "u", "p", "p2", "d"])
        XCTAssertEqual(StudioLines.statusWord("unprotected").word, "Not protected")
        XCTAssertEqual(StudioLines.agentCounts(agents[0]), "1 running, 2 idle, 4 finished \u{00B7} Today 3 actions, 1 asked, 0 refused")
    }

    func testSaysWhereAnExportedPackWent() {
        XCTAssertEqual(StudioLines.nothingToExport, "No rule set on this computer to export yet.")
        XCTAssertEqual(StudioLines.packSaved(1), "Saved 1 rule as TOML, ready to share.")
        XCTAssertEqual(StudioLines.packSaved(4), "Saved 4 rules as TOML, ready to share.")
        XCTAssertEqual(StudioLines.packCopied(4), "Copied 4 rules as TOML, ready to save or share.")
    }
}
