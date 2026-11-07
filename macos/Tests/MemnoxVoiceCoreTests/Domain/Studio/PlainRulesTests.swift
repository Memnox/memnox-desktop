import XCTest

@testable import MemnoxVoiceCore

final class PlainRulesTests: XCTestCase {
    private func rule(_ effect: RuleEffect, _ actions: [String], targets: [String]? = nil, agents: [String]? = nil,
                      classes: [String]? = nil, reason: String? = nil, name: String = "a") -> PolicyRuleView {
        PolicyRuleView(name: name, effect: effect.rawValue,
                       match: PolicyRuleMatch(actions: actions, targets: targets, agents: agents, classes: classes),
                       reason: reason, sentence: "raw", source: "user", editable: true)
    }

    private func plain(_ rule: PolicyRuleView) -> PlainRule {
        PlainRules.plain(rule) { $0 == "codex" ? "Codex" : $0 }
    }

    func testSaysEachFamilyInTheWordsWindowsAndLinuxUse() {
        let said: [(PolicyRuleView, String, RuleFamily)] = [
            (rule(.deny, ["filesystem.read", "environment.read"], targets: ["**/.ssh", "**/.ssh/**", "**/.aws", "!**/.env.example"]),
             "Reading secrets and credentials", .secrets),
            (rule(.ask, ["git.push-force", "git.branch-d", "git.reset-hard"]), "Force-pushing and hard resets", .destructiveGit),
            (rule(.ask, ["filesystem.delete"]), "Deleting files", .deletes),
            (rule(.ask, ["mcp.*"], classes: ["write", "destructive"]), "MCP tools that change something", .mcpTools),
            (rule(.ask, ["http.request"]), "Web requests that change something", .webRequests),
            (rule(.ask, ["psql.*", "!psql.insert", "mysql.*"]), "Database changes", .databaseWrites),
            (rule(.ask, ["aws.*", "gh.*", "vercel.*", "docker.push", "npm.publish"]), "Cloud, deploy and publish commands", .cloudTools),
            (rule(.ask, ["*", "!filesystem.*", "!file.*", "!shell.*", "!git.*"]), "Anything outside the usual coding tools", .outsideCodingTools),
            (rule(.deny, ["*"]), "Every action", .everything),
        ]
        for (each, title, family) in said {
            XCTAssertEqual(plain(each).title, title)
            XCTAssertEqual(plain(each).family, family)
        }
    }

    func testFallsBackToTheConsolesWordsOrAFewNamesAndACount() {
        XCTAssertEqual(plain(rule(.ask, ["git.tag"])).title, "Tagging a release")
        let push = PolicyRuleView(name: "p", effect: "ask", match: PolicyRuleMatch(actions: ["git.push"], branches: ["main"]),
                                  sentence: "raw", source: "user", editable: true)
        XCTAssertEqual(plain(push).title, "Pushing to main")
        let said = plain(rule(.deny, ["code.read", "test.run", "ticket.reply", "data.export", "llm.spend"]))
        XCTAssertEqual(said.title, "Read code, run tests, reply to a support ticket and 2 more")
        XCTAssertEqual(said.family, .other)
        XCTAssertEqual(plain(rule(.ask, ["ticket.reply"], targets: ["/support/**", "!/support/drafts"])).title,
                       "Reply to a support ticket in /support")
    }

    func testTakesTheReasonThenTheFamilysLineThenWhatTheEffectDoes() {
        let chosen = plain(rule(.deny, ["git.push-force"], reason: "you chose to deny this: it rewrites history somebody pulled"))
        XCTAssertEqual(chosen.why, "It rewrites history somebody pulled.")
        XCTAssertEqual(plain(rule(.ask, ["filesystem.delete"])).why, "Sometimes it really is the build folder, so a person should look first.")
        XCTAssertEqual(plain(rule(.ask, ["ticket.reply"], reason: "you chose to be asked about this")).why, "Waits for a person to say yes.")
    }

    func testSaysWhichAgentsARuleIsForApartFromItsTitle() {
        let said = plain(rule(.deny, ["filesystem.delete"], agents: ["codex"]))
        XCTAssertEqual(said.title, "Deleting files")
        XCTAssertEqual(said.caption, "Only for Codex. Sometimes it really is the build folder, so a person should look first.")
    }

    func testShowsRulesThatReadAndDoTheSameOnceWithACount() {
        let rules = [
            rule(.ask, ["*", "!git.*"], name: "one"),
            rule(.deny, ["filesystem.delete"], name: "two"),
            rule(.ask, ["*", "!filesystem.*"], name: "three"),
            rule(.deny, ["*", "!git.*"], name: "four"),
            rule(.ask, ["*", "!git.*"], agents: ["codex"], name: "five"),
        ]
        let groups = PlainRules.grouped(rules)
        XCTAssertEqual(groups.map(\.count), [2, 1, 1, 1])
        XCTAssertEqual(groups.first?.rules.map(\.name), ["one", "three"])
        XCTAssertEqual(PlainRules.countLine(2), "2 rules say this")
        XCTAssertNil(PlainRules.countLine(1))
    }

    func testKeepsThePatternAsWrittenForWhoeverWantsIt() {
        let written = PlainRules.written(PolicyRuleMatch(actions: ["filesystem.read"], targets: ["**/.ssh/**"]))
        XCTAssertEqual(written.map(\.label), ["Actions", "Targets"])
        XCTAssertEqual(written.last?.value, "**/.ssh/**")
        XCTAssertEqual(PlainRules.asWritten, "Show the rule as written")
    }
}
