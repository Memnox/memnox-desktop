import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The rules, the activity and the agents as the runtime's daemon/policies.ts, activity.ts and agents-view.ts write them.
final class StudioProtocolTests: XCTestCase {
    func testReadsTheRulesInForceWithWhereEachCameFrom() throws {
        let response = try line(#"{"id":1,"ok":true,"policyRules":{"rules":[{"name":"git-deny","effect":"deny","match":{"actions":["git.push-force"],"branches":["main"]},"sentence":"Deny force pushes","source":"file","file":"memnox.policies.toml","editable":false},{"name":"mine","effect":"ask","match":{"actions":["filesystem.delete"]},"reason":"files matter","sentence":"Ask before deleting","source":"person","until":"2026-11-01T00:00:00Z","editable":true}],"problems":[{"file":"broken.toml","issues":["no effect"]}],"missing":["gone.toml"]}}"#)
        let view = try XCTUnwrap(response.policyRules)
        XCTAssertEqual(view.rules.map(\.name), ["git-deny", "mine"])
        XCTAssertEqual(view.rules[0].ruleEffect, .deny)
        XCTAssertEqual(view.rules[0].ruleSource, .file)
        XCTAssertEqual(view.rules[0].match.branches, ["main"])
        XCTAssertNil(view.rules[0].match.agents)
        XCTAssertEqual(view.rules[1].reason, "files matter")
        XCTAssertTrue(view.rules[1].editable)
        XCTAssertEqual(view.problems.first?.issues, ["no effect"])
        XCTAssertEqual(view.missing, ["gone.toml"])
    }

    func testReadsProgressAsCountsAndTheLadder() throws {
        let week = #"{"from":"2026-10-26","asked":12,"answeredByAutopilot":3,"handedOver":1}"#
        let response = try line(#"{"id":2,"ok":true,"progress":{"ready":[{"action":"git.push","approvals":6,"targets":["origin"],"because":"You said yes 6 times"}],"almost":[{"action":"npm.publish","approvals":2,"needed":3}],"grants":[{"id":"g1","actions":["git.commit"],"targets":[],"agents":["claude-code"],"since":"2026-10-20T00:00:00Z","until":"2026-11-20T00:00:00Z","says":"Claude Code commits on its own"}],"autopilotOn":true,"ladder":{"level":"supervised","says":"Supervised","rungs":["observe","supervised","trusted"],"next":"trusted","needs":"A week with no refusal","actionsThisWeek":40,"asksThisWeek":12,"minimumEvidence":25},"thisWeek":"# + week + #","lastWeek":"# + week + "}}")
        let progress = try XCTUnwrap(response.progress)
        XCTAssertEqual(progress.ready.first?.homeReady, HomeReady(action: "git.push", approvals: 6, targets: ["origin"], because: "You said yes 6 times"))
        XCTAssertEqual(progress.almost, [ProgressAlmost(action: "npm.publish", approvals: 2, needed: 3)])
        XCTAssertEqual(progress.grants.first?.agents, ["claude-code"])
        XCTAssertEqual(progress.ladder.rungs, ["observe", "supervised", "trusted"])
        XCTAssertEqual(progress.ladder.next, "trusted")
        XCTAssertEqual(progress.thisWeek.answeredByAutopilot, 3)
    }

    func testReadsAPageOfActivityAndOneDecisionWhole() throws {
        let row = #"{"id":"r1","at":"2026-10-30T10:00:00Z","agent":"claude-code","agentName":"Claude Code","session":"s1","kind":"command","operation":"git.push","target":"origin","effect":"ask","rule":"push-main","reason":"main is shared","answeredBy":"Sam","answeredHow":"within-session","failed":1}"#
        let page = try XCTUnwrap(try line(#"{"id":3,"ok":true,"activity":{"rows":["# + row + #"],"nextCursor":"c1"}}"#).activity)
        XCTAssertEqual(page.nextCursor, "c1")
        let first = try XCTUnwrap(page.rows.first)
        XCTAssertEqual(first.activityKind, .command)
        XCTAssertEqual(first.answered, .withinSession)
        XCTAssertEqual(first.failed, 1)
        XCTAssertNil(first.shadowEffect)
        let decision = try XCTUnwrap(try line(#"{"id":4,"ok":true,"decision":{"row":"# + row + #","rule":{"name":"push-main","source":"workspace","decidedBy":"Ada","newerSince":true},"chain":"Sam, Claude Code","context":[{"domain":"repository","facts":["on main"],"decided":true}],"before":[{"at":"2026-10-30T09:59:00Z","operation":"git.commit","effect":"allow"}],"alternative":"Open a pull request","trace":{"mode":"enforce","exitCode":1,"approvedBy":"Sam"}}}"#).decision)
        XCTAssertEqual(decision.rule?.newerSince, true)
        XCTAssertEqual(decision.context.first?.decided, true)
        XCTAssertEqual(decision.before.first?.ruleEffect, .allow)
        XCTAssertEqual(decision.trace.approvedBy, "Sam")
        XCTAssertNil(decision.task)
    }

    func testReadsEveryAgentWithItsStanding() throws {
        let response = try line(#"{"id":5,"ok":true,"agentsView":[{"kind":"codex-cli","name":"Codex","status":"paused","pausedUntil":"2026-10-31T00:00:00Z","sessions":{"running":0,"idle":1,"finished":4},"mcpServers":["github"],"today":{"actions":3,"asked":1,"refused":0},"recent":[{"id":"a1","at":"2026-10-30T10:00:00Z","operation":"git.push","effect":"deny"}]}]}"#)
        let agent = try XCTUnwrap(response.agentsView?.first)
        XCTAssertEqual(agent.agentStatus, .paused)
        XCTAssertEqual(agent.sessions.finished, 4)
        XCTAssertEqual(agent.recent.first?.ruleEffect, .deny)
        XCTAssertNil(agent.configPath)
    }

    func testReadsAVerdictAnExportAndAPack() throws {
        let verdict = try XCTUnwrap(try line(#"{"id":6,"ok":true,"ruleVerdict":{"effect":"deny","reason":"never force push","rule":"git-deny","instead":"push a branch"}}"#).ruleVerdict)
        XCTAssertEqual(verdict.ruleEffect, .deny)
        XCTAssertEqual(verdict.instead, "push a branch")
        XCTAssertEqual(try line(#"{"id":7,"ok":true,"rulesToml":"[[policies]]\n"}"#).rulesToml, "[[policies]]\n")
        XCTAssertEqual(try line(#"{"id":8,"ok":true,"packProposed":["prp_1","prp_2"]}"#).packProposed, ["prp_1", "prp_2"])
        XCTAssertEqual(try line(#"{"id":9,"ok":true,"activityBundle":"{}\n"}"#).activityBundle, "{}\n")
    }

    func testAnOlderDaemonLeavesEveryPartOut() throws {
        let response = try line(#"{"id":10,"ok":false,"error":"unknown method rules"}"#)
        XCTAssertNil(response.policyRules)
        XCTAssertNil(response.progress)
        XCTAssertNil(response.activity)
        XCTAssertNil(response.decision)
        XCTAssertNil(response.agentsView)
        XCTAssertEqual(response.error, "unknown method rules")
    }

    func testAnUnknownEffectOrStatusIsKeptButNotNamed() throws {
        let response = try line(#"{"id":11,"ok":true,"agentsView":[{"kind":"x","name":"X","status":"sleeping","sessions":{"running":0,"idle":0,"finished":0},"mcpServers":[],"today":{"actions":0,"asked":0,"refused":0},"recent":[{"id":"a","at":"","operation":"y","effect":"redact"}]}]}"#)
        let agent = try XCTUnwrap(response.agentsView?.first)
        XCTAssertNil(agent.agentStatus)
        XCTAssertEqual(agent.status, "sleeping")
        XCTAssertNil(agent.recent.first?.ruleEffect)
    }

    func testWritesARuleDraftWithOnlyTheFieldsFilledIn() throws {
        var request = DaemonRequest(id: 12, method: .rulePropose)
        request.ruleDraft = RuleDraftInput(effect: .ask, action: "git.push", branches: ["main"], reason: "main is shared")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(request)) as? [String: Any])
        XCTAssertEqual(object["method"] as? String, "rule-propose")
        let draft = try XCTUnwrap(object["ruleDraft"] as? [String: Any])
        XCTAssertEqual(draft["effect"] as? String, "ask")
        XCTAssertEqual(draft["branches"] as? [String], ["main"])
        XCTAssertNil(draft["agents"])
        XCTAssertNil(draft["targets"])
    }

    func testWritesAFilterACursorAndAnAgent() throws {
        var request = DaemonRequest(id: 13, method: .activity)
        request.activityFilter = ActivityFilter(effect: .deny, kind: .mcp, text: "push")
        request.activityCursor = "c1"
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(request)) as? [String: Any])
        XCTAssertEqual(object["activityFilter"] as? [String: String], ["effect": "deny", "kind": "mcp", "text": "push"])
        XCTAssertEqual(object["activityCursor"] as? String, "c1")
        var pause = DaemonRequest(id: 14, method: .agentPause)
        pause.agentKind = "codex-cli"
        let paused = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(pause)) as? [String: Any])
        XCTAssertEqual(paused["agentKind"] as? String, "codex-cli")
        XCTAssertNil(paused["activityFilter"])
    }

    func testNamesEveryMethodAsTheRuntimeDoes() {
        let methods: [DaemonMethod] = [.rules, .rulePropose, .ruleRemove, .ruleTest, .rulesExport, .rulePackImport, .progress,
                                       .autopilotRevoke, .activity, .decision, .activityExport, .agents, .agentPause,
                                       .agentResume, .sessionStop]
        XCTAssertEqual(methods.map(\.rawValue), ["rules", "rule-propose", "rule-remove", "rule-test", "rules-export",
                                                 "rule-pack-import", "progress", "autopilot-revoke", "activity", "decision",
                                                 "activity-export", "agents", "agent-pause", "agent-resume", "session-stop"])
    }
}
