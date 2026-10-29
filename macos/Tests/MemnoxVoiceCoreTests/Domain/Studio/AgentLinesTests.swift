import XCTest

@testable import MemnoxVoiceCore

final class AgentLinesTests: XCTestCase {
    private func agents() throws -> [AgentStanding] {
        let json = #"""
        [{"kind":"code","name":"Claude Code","status":"protected","sessions":{"running":1,"idle":0,"finished":3},"mcpServers":[],
          "today":{"actions":12,"asked":2,"refused":0},"recent":[]},
         {"kind":"desk","name":"Claude Desktop","status":"unprotected","sessions":{"running":0,"idle":0,"finished":0},"mcpServers":[],
          "today":{"actions":0,"asked":0,"refused":0},"recent":[]},
         {"kind":"cur","name":"Cursor","status":"protected","sessions":{"running":0,"idle":2,"finished":0},"mcpServers":[],
          "today":{"actions":0,"asked":0,"refused":0},"recent":[]}]
        """#
        return try JSONDecoder().decode([AgentStanding].self, from: Data(json.utf8))
    }

    func testSumsUpThePageInCounts() throws {
        XCTAssertEqual(AgentLines.summary(try agents()), "3 agents, 2 protected, 1 running")
    }

    func testOffersRunningAndPausedAlwaysAndNotProtectedOnlyWhileSomeAgentIs() throws {
        let list = try agents()
        XCTAssertEqual(AgentLines.filters(list), [.all, .running, .unprotected, .paused])
        XCTAssertEqual(AgentLines.filters([list[0]]), [.all, .running, .paused])
        XCTAssertEqual(AgentLines.count(list, .paused), 0)
        XCTAssertEqual(AgentLines.shown(list, .all).map(\.kind), ["desk", "code", "cur"])
        XCTAssertEqual(AgentLines.shown(list, .running).map(\.kind), ["code"])
        XCTAssertEqual(AgentLines.count(list, .unprotected), 1)
    }

    func testShowsOnlyTheNumbersThatSaySomething() throws {
        let list = try agents()
        XCTAssertEqual(AgentLines.figures(list[0]).map(\.label), ["Running", "Today", "Asked"])
        XCTAssertEqual(AgentLines.figures(list[0]).map(\.value), [1, 12, 2])
        XCTAssertTrue(AgentLines.figures(list[2]).isEmpty)
    }

    func testNamesTheAgentsRunningOutsideMemnox() throws {
        XCTAssertEqual(AgentLines.needsProtecting(try agents()), "Claude Desktop is not protected")
        XCTAssertNil(AgentLines.needsProtecting([]))
    }

    func testNamesATargetByItsLastParts() throws {
        let json = #"[{"id":"1","at":"2026-10-31T10:00:00Z","operation":"filesystem.write","target":"/Users/me/code/Memnox-saas/app/main.swift","effect":"allow"},{"id":"2","at":"2026-10-31T10:00:00Z","operation":"git.push","target":" ","effect":"ask"}]"#
        let actions = try JSONDecoder().decode([AgentAction].self, from: Data(json.utf8))
        XCTAssertEqual(AgentLines.target(actions[0]), "app/main.swift")
        XCTAssertNil(AgentLines.target(actions[1]))
    }

    func testLeadsWithProtectForAnAgentOutsideMemnox() throws {
        let list = try agents()
        XCTAssertEqual(AgentLines.press(list[0]), .pause)
        XCTAssertEqual(AgentLines.press(list[1]), .protect)
    }

    func testSaysWhenItWasLastActiveAndWhatItReaches() throws {
        let json = #"""
        {"kind":"code","name":"Claude Code","status":"protected","sessions":{"running":0,"idle":0,"finished":0},"mcpServers":["github"],
         "skills":["a","b"],"today":{"actions":0,"asked":0,"refused":0},
         "recent":[{"id":"1","at":"2026-10-28T10:00:00Z","operation":"git.push","effect":"allow"}]}
        """#
        let agent = try JSONDecoder().decode(AgentStanding.self, from: Data(json.utf8))
        let now = try XCTUnwrap(readInstant("2026-10-31T10:00:00Z"))
        XCTAssertEqual(AgentLines.reachLine(agent, now: now), "Last active 3 d ago \u{00B7} 2 skills \u{00B7} 1 MCP server")
        XCTAssertEqual(AgentLines.reachLine(try agents()[1], now: now), "No activity seen yet \u{00B7} 0 skills \u{00B7} 0 MCP servers")
    }

    func testShowsAFewSkillsAsChipsAndCountsTheRest() {
        XCTAssertEqual(AgentLines.chips(["a", "b", "c", "d"], limit: 3), AgentChips(shown: ["a", "b", "c"], more: 1))
        XCTAssertEqual(AgentLines.chips(nil, limit: 3), AgentChips(shown: [], more: 0))
    }

    private func desktop(_ status: String, seam: String?) throws -> AgentStanding {
        let held = seam.map { #","seam":"\#($0)""# } ?? ""
        let json = #"{"kind":"claude-desktop","name":"Claude Desktop","status":"\#(status)"\#(held),"sessions":{"running":0,"idle":0,"finished":0},"mcpServers":[],"today":{"actions":0,"asked":0,"refused":0},"recent":[]}"#
        return try JSONDecoder().decode(AgentStanding.self, from: Data(json.utf8))
    }

    func testSaysToReopenAnAgentHeldThroughItsServersOnceItIsProtected() throws {
        let result = AgentLines.afterProtect(["claude-desktop"], agents: [try desktop("protected", seam: "servers")], failed: nil)
        XCTAssertTrue(result.held)
        XCTAssertEqual(result.line, "Claude Desktop is protected. Quit and open Claude Desktop again so its servers start through Memnox.")
        XCTAssertTrue(result.covers("claude-desktop"))
        XCTAssertFalse(result.covers("claude-code"))
    }

    func testSaysWhatStillKeepsAnAgentOutsideAfterProtect() throws {
        let servers = AgentLines.afterProtect(["claude-desktop"], agents: [try desktop("unprotected", seam: "servers")], failed: nil)
        XCTAssertFalse(servers.held)
        XCTAssertTrue(servers.line.hasPrefix("Claude Desktop still starts a server outside Memnox"))
        let hooked = try code()
        let none = AgentLines.afterProtect(["claude-desktop"], agents: [hooked, try desktop("unprotected", seam: nil)], failed: nil)
        XCTAssertEqual(none.line, "Memnox has no way into Claude Desktop yet, so Protect cannot hold it.")
        XCTAssertNil(none.followUp)
        let hook = AgentLines.afterProtect(["claude-desktop"], agents: [try desktop("unprotected", seam: "hook")], failed: nil)
        XCTAssertTrue(hook.line.contains("its hook did not go in"))
    }

    private func code() throws -> AgentStanding {
        let json = #"{"kind":"claude-code","name":"Claude Code","status":"protected","seam":"hook","sessions":{"running":0,"idle":0,"finished":0},"mcpServers":[],"today":{"actions":0,"asked":0,"refused":0},"recent":[]}"#
        return try JSONDecoder().decode(AgentStanding.self, from: Data(json.utf8))
    }

    func testOffersARestartWhenTheServiceIsTooOldToSeeAnAgentIsHeld() throws {
        let old = [try desktop("unprotected", seam: nil)]
        XCTAssertTrue(AgentLines.runtimePredatesSeams(old))
        let result = AgentLines.afterProtect(["claude-desktop"], agents: old, failed: nil)
        XCTAssertFalse(result.held)
        XCTAssertEqual(result.followUp, .restartService)
        XCTAssertEqual(result.line, "The Memnox service on this Mac is older than this app, so it cannot see that Claude Desktop is held. "
            + "Restart it to run the newer runtime.")
        let again = AgentLines.afterProtect(["claude-desktop"], agents: old, failed: nil, restarted: true)
        XCTAssertTrue(again.line.hasPrefix("The Memnox service restarted but still runs a runtime older than this app"))
        XCTAssertEqual(again.followUp, .restartService)
    }

    func testANewServiceIsNotTakenForAnOldOne() throws {
        XCTAssertFalse(AgentLines.runtimePredatesSeams([try code(), try desktop("unprotected", seam: nil)]))
        XCTAssertFalse(AgentLines.runtimePredatesSeams([]))
        let fresh = AgentLines.afterProtect(["claude-desktop"], agents: [try desktop("protected", seam: "servers")], failed: nil)
        XCTAssertNil(fresh.followUp)
    }

    func testCarriesTheReasonAProtectFailed() throws {
        let result = AgentLines.afterProtect(["claude-desktop"], agents: [try desktop("protected", seam: "hook")], failed: "No memnox here.")
        XCTAssertEqual(result, ProtectResult(kinds: ["claude-desktop"], line: "No memnox here.", held: false))
    }

    func testPressesProtectForEveryAgentOutsideMemnox() throws {
        XCTAssertEqual(AgentLines.unprotectedKinds(try agents()), ["desk"])
        XCTAssertEqual(try agents()[1].agentSeam, nil)
        XCTAssertEqual(try desktop("protected", seam: "servers").agentSeam, .servers)
    }
}
