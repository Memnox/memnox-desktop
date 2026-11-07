import XCTest
@testable import MemnoxVoiceCore

/// Checks the demo world both desktop apps answer from still decodes through the protocol this app reads, so a change
/// to the wire that the fixture has not followed fails here rather than as an empty page in the demo.
final class DemoLinkTests: XCTestCase {
    /// The fixture as `shared/demo/power-user.json` keeps it beside every desktop app: six folders up from this file,
    /// or beside macos/ when the tests run from a copy of themselves.
    private func fixture() throws -> Data {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            here.appendingPathComponent("shared/demo/power-user.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("../shared/demo/power-user.json"),
        ]
        let found = try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0.path) }, "no shared/demo/power-user.json")
        return try Data(contentsOf: found)
    }

    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func link() throws -> DemoLink {
        try DemoLink(fixture: fixture(), now: { [now] in now })
    }

    private func ask(_ link: DemoLink, _ method: DaemonMethod, _ shape: (inout DaemonRequest) -> Void = { _ in }) async throws -> DaemonResponse {
        var request = DaemonRequest(id: 7, method: method)
        shape(&request)
        return try await link.request(request)
    }

    func testDecodesEveryPieceOfTheFixture() throws {
        let lines = try link().everyLine()
        XCTAssertGreaterThan(lines.count, 50)
        for (name, line) in lines {
            let data = try JSONEncoder().encode(line.with("id", .number(1)))
            // Decoded straight, so a failure names the field rather than the whole line.
            XCTAssertNoThrow(try JSONDecoder().decode(DaemonResponse.self, from: data), name)
        }
    }

    func testFillsEveryFieldTheFixtureNames() throws {
        for (name, line) in try link().everyLine() {
            let response = try DemoLink.response(line, id: 1)
            let filled = Dictionary(uniqueKeysWithValues: Mirror(reflecting: response).children.compactMap { child in
                child.label.map { ($0, !Self.isNone(child.value)) }
            })
            for key in line.fields.keys where key != "id" {
                // A misspelled field decodes as nothing at all, so each one written must land somewhere.
                XCTAssertEqual(filled[key], true, "\(name) writes \(key), which the protocol does not read")
            }
        }
    }

    private static func isNone(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }

    func testHoldsAPowerUsersDay() async throws {
        let link = try link()
        let projects = try await ask(link, .projects).projects?.projects ?? []
        XCTAssertEqual(projects.count, 7)
        XCTAssertEqual(projects.filter { $0.organization != nil }.count, 1)
        let waiting = try await ask(link, .waiting)
        XCTAssertEqual(waiting.waiting?.count, 5)
        let sessionsList = try await ask(link, .sessionsList)
        XCTAssertGreaterThanOrEqual(sessionsList.sessions?.count ?? 0, 10)
        let agents = try await ask(link, .agents)
        XCTAssertEqual(Set(agents.agentsView?.map(\.kind) ?? []), ["claude-code", "codex-cli", "cursor", "gemini-cli", "windsurf"])
        let activity = try await ask(link, .activity)
        XCTAssertEqual(activity.activity?.rows.count, 60)
        let rules = try await ask(link, .rules)
        XCTAssertGreaterThanOrEqual(rules.policyRules?.rules.count ?? 0, 25)
        let skillsHub = try await ask(link, .skillsHub)
        XCTAssertGreaterThanOrEqual(skillsHub.skillsHub?.skills.count ?? 0, 40)
        let mcpHub = try await ask(link, .mcpHub)
        XCTAssertEqual(mcpHub.mcpHub?.servers.count, 10)
        let connectionsList = try await ask(link, .connectionsList)
        XCTAssertEqual(connectionsList.connections?.filter(\.connected).count, 8)
        let memorySources = try await ask(link, .memorySources)
        XCTAssertEqual(memorySources.memorySources?.count, 10)
        let memoryFacts = try await ask(link, .memoryFacts)
        XCTAssertGreaterThanOrEqual(memoryFacts.memoryFacts?.items.count ?? 0, 45)
        let memoryLearn = try await ask(link, .memoryLearn)
        XCTAssertFalse(memoryLearn.memoryLearn?.items.isEmpty ?? true)
        let devicesList = try await ask(link, .devicesList)
        XCTAssertEqual(devicesList.devices?.count, 1)
        let machine = try await ask(link, .machine)
        XCTAssertEqual(machine.machine?.name, "Acme")
        XCTAssertEqual(link.personName, "Alex Rivera")
    }

    func testKeepsEveryNodeOfTheMemoryMap() async throws {
        let link = try link()
        let written = try JSONDecoder().decode(DemoJSON.self, from: fixture())["answers"]?["workspace-graph"]?["workspaceGraph"]?["nodes"]?.items.count
        // The graph drops a node it cannot read rather than failing, so the count is what proves each one decoded.
        let workspaceGraph = try await ask(link, .workspaceGraph)
        XCTAssertEqual(workspaceGraph.workspaceGraph?.nodes.count, written)
    }

    func testWritesEveryTimeAsSomeMomentBeforeNow() async throws {
        let rows = try await ask(try link(), .activity).activity?.rows ?? []
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let at = try XCTUnwrap(DemoTime.date(row.at), row.at)
            XCTAssertLessThanOrEqual(at, now)
        }
        XCTAssertEqual(DemoTime.stamp("$now-5m", now: now), DemoTime.iso(now.addingTimeInterval(-300)))
        XCTAssertEqual(DemoTime.stamp("$now+2d", now: now), DemoTime.iso(now.addingTimeInterval(2 * 86_400)))
        XCTAssertNil(DemoTime.stamp("$nowhere", now: now))
    }

    func testSettlesAnAnsweredCallHereAlone() async throws {
        let link = try link()
        var confirm = DaemonRequest(id: 8, method: .confirm)
        confirm.subject = "hold_web_push_main"
        confirm.answer = HoldAnswer.once.rawValue
        let confirmed = try await link.request(confirm)
        XCTAssertTrue(confirmed.ok)
        let waiting = try await ask(link, .waiting)
        XCTAssertEqual(waiting.waiting?.count, 4)
        let home = try await ask(link, .home)
        XCTAssertEqual(home.home?.waiting, 4)
    }

    func testNarrowsTheLedgerAsActivityAsks() async throws {
        let link = try link()
        let refused = try await ask(link, .activity) { $0.activityFilter = ActivityFilter(effect: .deny) }
        XCTAssertFalse(refused.activity?.rows.isEmpty ?? true)
        XCTAssertTrue(refused.activity?.rows.allSatisfy { $0.effect == RuleEffect.deny.rawValue } ?? false)
        let today = try await ask(link) { $0.activityFilter = ActivityFilter(since: DemoTime.iso(self.now.addingTimeInterval(-3600))) }
        XCTAssertLessThan(today.activity?.rows.count ?? 0, 60)
    }

    private func ask(_ link: DemoLink, shape: (inout DaemonRequest) -> Void) async throws -> DaemonResponse {
        try await ask(link, .activity, shape)
    }

    func testAnswersAWriteWithItsPageAndRefusesWhatOnlyADaemonDoes() async throws {
        let link = try link()
        let proposed = try await ask(link, .rulePropose)
        XCTAssertEqual(proposed.policyRules?.rules.isEmpty, false)
        let signIn = try await ask(link, .connectionsSignIn)
        XCTAssertFalse(signIn.ok)
        XCTAssertEqual(signIn.error, link.demoOnly)
    }

    func testOpensASubscriptionWithTheHeldCallsAndTheHandedBackSession() async throws {
        var request = DaemonRequest(id: 9, method: .subscribe)
        request.subscribeActivity = true
        var kinds: [EventKind] = []
        for try await response in try link().stream(request) {
            if let kind = response.event?.eventKind { kinds.append(kind) }
            if kinds.count == 6 { break }
        }
        XCTAssertEqual(kinds.filter { $0 == .held }.count, 5)
        XCTAssertEqual(kinds.last, .notice)
    }

    /// Every reader a page waits on, read through the demo the way the window reads it, so no page spins on nothing.
    func testFillsEveryPageTheWindowReads() async throws {
        let link = try self.link()
        let agents = Agents(link: link)
        await agents.refresh()
        XCTAssertFalse(agents.unreadable, "agents")
        XCTAssertEqual(agents.agents?.count, 5, "agents")
        let projects = Projects(link: link)
        await projects.refresh()
        XCTAssertEqual(projects.projects?.count, 7, "projects")
        let studio = Studio(link: link)
        await studio.refresh()
        XCTAssertGreaterThan(studio.rules?.rules.count ?? 0, 20, "rules")
        let hub = McpHub(link: link)
        await hub.refresh()
        XCTAssertNotNil(hub.hub, "mcp hub")
        let memory = Memory(link: link)
        await memory.refreshSources()
        XCTAssertGreaterThan(memory.sources?.count ?? 0, 0, "memory sources")
        let layers = MemoryLayers(link: link)
        await layers.refresh()
        XCTAssertNotNil(layers.layers, "memory layers")
    }
}
