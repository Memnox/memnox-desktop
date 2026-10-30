import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/studio.test.ts, so the Mac keeps rules, activity and agents the way Windows and Linux do.
final class StudioTests: XCTestCase {
    private static let rules = #"{"rules":[{"name":"git-deny","effect":"deny","match":{"actions":["git.push-force"]},"sentence":"Deny force pushes","source":"file","file":"memnox.policies.toml","editable":false},{"name":"mine","effect":"ask","match":{"actions":["filesystem.delete"]},"sentence":"Ask before deleting","source":"person","editable":true}],"problems":[],"missing":[]}"#

    private static func row(_ id: String) -> String {
        #"{"id":""# + id + #"","at":"2026-10-30T10:00:00Z","agent":"claude-code","agentName":"Claude Code","session":"s","kind":"command","operation":"git.push","effect":"ask","reason":"asked"}"#
    }

    func testSaysANewRuleWaitsForASignatureRatherThanClaimingItIsInForce() async throws {
        let link = ScriptedLink()
        link.answers["rule-propose"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_9"}"#)]
        let studio = Studio(link: link)
        let outcome = await studio.propose(RuleDraftInput(effect: .ask, action: "git.push", branches: ["main"], reason: "main is shared"))
        XCTAssertEqual(outcome, .proposed("prp_9"))
        let sent = try XCTUnwrap(link.sent.first?.ruleDraft)
        XCTAssertEqual(sent.action, "git.push")
        XCTAssertEqual(sent.branches, ["main"])
        XCTAssertNil(studio.busy)
    }

    func testReadsRulesAndProgressTogetherAndSaysWhenTheRulesCouldNotBeRead() async throws {
        let link = ScriptedLink()
        link.answers["rules"] = [try line(#"{"id":1,"ok":true,"policyRules":"# + Self.rules + "}")]
        link.answers["progress"] = [try line(#"{"id":2,"ok":false,"error":"no method progress"}"#)]
        let studio = Studio(link: link)
        await studio.refresh()
        XCTAssertEqual(studio.rules?.rules.count, 2)
        XCTAssertNil(studio.progress)
        XCTAssertFalse(studio.unreadable)

        let away = ScriptedLink()
        away.unreachable = true
        let lost = Studio(link: away)
        await lost.refresh()
        XCTAssertTrue(lost.unreadable)
        let removed = await lost.remove("mine")
        XCTAssertEqual(removed, .failed("The runtime is not answering."))
    }

    func testRemovingAnAllowIsDoneAtOnceAndRedrawsFromTheAnswer() async throws {
        let link = ScriptedLink()
        link.answers["rule-remove"] = [try line(#"{"id":1,"ok":true,"policyRules":"# + Self.rules + "}")]
        let studio = Studio(link: link)
        let outcome = await studio.remove("mine")
        XCTAssertEqual(outcome, .done("mine is no longer in force."))
        XCTAssertEqual(link.sent.first?.ruleName, "mine")
        XCTAssertEqual(studio.rules?.rules.map(\.name), ["git-deny", "mine"])
    }

    func testCountsAPackAsOneProposalPerRule() async throws {
        let link = ScriptedLink()
        link.answers["rule-pack-import"] = [try line(#"{"id":1,"ok":true,"packProposed":["a","b"]}"#)]
        let outcome = await Studio(link: link).importPack("[[policies]]\n[[policies]]\n")
        XCTAssertEqual(outcome, .done("2 rules wait for your signature on the island."))
        XCTAssertEqual(link.sent.first?.rulePack, "[[policies]]\n[[policies]]\n")
    }

    func testTriesAnActionAndPassesOnTheRuntimesRefusal() async throws {
        let link = ScriptedLink()
        link.answers["rule-test"] = [try line(#"{"id":1,"ok":true,"ruleVerdict":{"effect":"deny","reason":"never","rule":"git-deny"}}"#)]
        let studio = Studio(link: link)
        guard case .verdict(let verdict) = await studio.test(RuleTestInput(action: "git push --force")) else {
            return XCTFail("expected a verdict")
        }
        XCTAssertEqual(verdict.rule, "git-deny")
        link.answers["rule-test"] = [try line(#"{"id":2,"ok":false,"error":"no action"}"#)]
        let refused = await studio.test(RuleTestInput(action: ""))
        XCTAssertEqual(refused, .failed("no action"))
    }

    func testReadsOnFromWhereTheLastPageStoppedAndStartsOverWhenTheFilterChanges() async throws {
        let link = ScriptedLink()
        link.answers["activity"] = [try line(#"{"id":1,"ok":true,"activity":{"rows":["# + Self.row("a") + #"],"nextCursor":"c1"}}"#)]
        let activity = Activity(link: link)
        await activity.show(ActivityFilter(effect: .ask))
        XCTAssertTrue(activity.more)
        link.answers["activity"] = [try line(#"{"id":2,"ok":true,"activity":{"rows":["# + Self.row("b") + "]}}")]
        await activity.readOn()
        XCTAssertEqual(activity.rows.map(\.id), ["a", "b"])
        XCTAssertFalse(activity.more)
        XCTAssertEqual(link.sent[1].activityCursor, "c1")
        XCTAssertEqual(link.sent[1].activityFilter, ActivityFilter(effect: .ask))

        await activity.show(ActivityFilter(kind: .mcp))
        XCTAssertEqual(activity.rows.map(\.id), ["b"])
        XCTAssertNil(link.sent[2].activityCursor)
    }

    func testOpensOneDecisionAndClosesIt() async throws {
        let link = ScriptedLink()
        link.answers["decision"] = [try line(#"{"id":1,"ok":true,"decision":{"row":"# + Self.row("a") + #","chain":"Sam","context":[],"before":[],"trace":{"mode":"enforce"}}}"#)]
        let activity = Activity(link: link)
        await activity.open("a")
        XCTAssertEqual(activity.decision?.row.id, "a")
        XCTAssertEqual(link.sent.first?.decisionId, "a")
        activity.close()
        XCTAssertNil(activity.decision)
    }

    func testPassesResumingOnForASignatureSinceItGivesAnAgentBackItsReach() async throws {
        let link = ScriptedLink()
        link.answers["agent-resume"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_r"}"#)]
        let outcome = await Agents(link: link).resume("codex-cli")
        XCTAssertEqual(outcome, .proposed("prp_r"))
        XCTAssertEqual(link.sent.first?.agentKind, "codex-cli")
    }

    func testPausingIsDoneAtOnceAndSaidSo() async throws {
        let link = ScriptedLink()
        link.answers["agent-pause"] = [try line(#"{"id":1,"ok":true}"#)]
        let agents = Agents(link: link)
        let outcome = await agents.pause("codex-cli")
        XCTAssertEqual(outcome, .done("Paused. Nothing it tries runs until you resume it."))
        XCTAssertNil(agents.busy)
    }
}
