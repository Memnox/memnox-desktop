import XCTest

@testable import MemnoxVoiceCore

/// Today puts what blocks an agent first, then the oldest, and offers only the choices the runtime takes.
final class TodayBoardTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // A fixed zone, so local midnight is the same wherever the tests run.
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
    private let now = ISO8601DateFormatter().date(from: "2026-11-01T13:14:00Z") ?? Date()

    private func rows(_ json: String) throws -> [ActivityRow] {
        try JSONDecoder().decode([ActivityRow].self, from: Data(json.utf8))
    }

    private func row(_ id: String, at: String, effect: String, session: String = "s1", operation: String = "git.push",
                     failed: Int? = nil, answeredBy: String? = nil) -> String {
        let fail = failed.map { #","failed":\#($0)"# } ?? ""
        let by = answeredBy.map { #","answeredBy":"\#($0)""# } ?? ""
        return #"{"id":"\#(id)","at":"\#(at)","agent":"claude-code","agentName":"Claude Code","session":"\#(session)","kind":"command","operation":"\#(operation)","target":"origin","effect":"\#(effect)","rule":"no-push","reason":"held by rule"\#(fail)\#(by)}"#
    }

    private func held(_ subject: String, at: String, team: Bool = false) -> TodayHeld {
        TodayHeld(subject: subject, agent: "codex", who: "Codex on your Mac", what: "rm -rf build", why: "deletes files",
                  at: at, team: team, sessionId: "s2")
    }

    func testPutsWhatBlocksAnAgentFirstThenTheOldest() throws {
        let activity = try rows("[" + row("r1", at: "2026-11-01T09:00:00Z", effect: "deny") + "]")
        let working = SessionCard(sessionId: "w", agent: "claude-code", agentName: "Claude Code", task: "tests", state: "working",
                                  lastActive: "2026-11-01T08:00:00Z")
        let back = SessionCard(sessionId: "b", agent: "codex", agentName: "Codex", task: "docs", state: "open",
                               lastActive: "2026-11-01T07:00:00Z")
        let sources = TodaySources(held: [held("late", at: "2026-11-01T12:00:00Z"), held("early", at: "2026-11-01T10:00:00Z")],
                                   sessions: [working, back], activity: activity, owed: ["Turn on Touch ID"])
        let ids = TodayBoard.overview(sources, now: now, calendar: calendar).map(\.id)
        XCTAssertEqual(ids, ["stopped:r1", "held:early", "held:late", "session:b", "owed:Turn on Touch ID", "session:w"])
    }

    func testNamesTheProjectEachItemHappensIn() {
        let web = ProjectView(id: "p1", name: "Website", path: "/code/web", declared: true, opened: true, agents: [], agentsSeen: [],
                              sessions: ProjectSessionsView(total: 0, ended: 0), servers: [], skills: [],
                              rules: ProjectRulesView(count: 0, inForce: false), instructions: [], memoryScope: "project",
                              openMissions: [], openQuestions: 0)
        let call = TodayHeld(subject: "h", agent: "codex", who: "Codex", what: "rm -rf build", why: "deletes files",
                             at: "2026-11-01T12:00:00Z", place: "web")
        let card = SessionCard(sessionId: "b", agent: "codex", agentName: "Codex", task: "docs", state: "open", repository: "/code/web/docs")
        let items = TodayBoard.overview(TodaySources(held: [call], sessions: [card], projects: [web]), now: now, calendar: calendar)
        XCTAssertEqual(items.map(\.project), ["Website", "Website"])
        XCTAssertEqual(items.first.flatMap(TodayLines.under), "In Website\(SessionText.separator)deletes files")
        XCTAssertEqual(items.last.flatMap(TodayLines.under), "In Website")
    }

    func testSectionsFollowTheItemsAndDropAnEmptyOne() throws {
        let sources = TodaySources(held: [held("a", at: "2026-11-01T12:00:00Z")], owed: ["Sign in"])
        let sections = TodayBoard.sections(TodayBoard.overview(sources, now: now, calendar: calendar))
        XCTAssertEqual(sections.map(\.section), [.needsYou, .next])
        XCTAssertEqual(TodaySection.needsYou.title, "Needs you, most urgent first")
    }

    func testFoldsTheSameRefusalIntoOneLineWithItsCount() throws {
        let activity = try rows("[" + [row("r1", at: "2026-11-01T09:00:00Z", effect: "deny"),
                                       row("r2", at: "2026-11-01T11:00:00Z", effect: "deny"),
                                       row("old", at: "2026-10-31T11:00:00Z", effect: "deny")].joined(separator: ",") + "]")
        let items = TodayBoard.overview(TodaySources(activity: activity), now: now, calendar: calendar)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, .refused(count: 2))
        XCTAssertEqual(items.first?.state, .stopped)
        XCTAssertEqual(items.first?.detail, "Refused by no-push, 2 times today")
    }

    func testOffersTheIslandsAnswersAndLeavesFromNowOnOffATeammatesCall() {
        XCTAssertEqual(TodayBoard.heldChoices(team: false).map(\.title), ["Allow once", "Allow this session", "Allow from now on", "Deny"])
        XCTAssertEqual(TodayBoard.heldChoices(team: false).map(\.key), ["A", "B", "C", "D"])
        XCTAssertEqual(TodayBoard.heldChoices(team: true).map(\.action), [.answer(.once), .answer(.session), .answer(.deny)])
        // Nothing is marked recommended unless the runtime said so.
        XCTAssertFalse(TodayBoard.heldChoices(team: false).contains { $0.recommended })
    }

    func testMarksOnlyWhatTheRuntimeRecommends() {
        let ready = HomeReady(action: "git push", approvals: 5, targets: [], because: "you said yes five times and never no")
        let item = TodayBoard.overview(TodaySources(ready: ready), now: now, calendar: calendar).first
        XCTAssertEqual(item?.recommendation, "you said yes five times and never no")
        XCTAssertEqual(item?.choices.first { $0.recommended }?.action, .handOver)
        XCTAssertEqual(item.flatMap(TodayLines.under), "Recommend: you said yes five times and never no")
        let call = TodayBoard.overview(TodaySources(held: [held("a", at: "2026-11-01T12:00:00Z")]), now: now, calendar: calendar).first
        XCTAssertNil(call?.recommendation)
        XCTAssertEqual(call.flatMap(TodayLines.under), "deletes files")
    }

    func testALetterPressesItsChoiceInEitherCase() {
        let item = TodayBoard.overview(TodaySources(held: [held("a", at: "2026-11-01T12:00:00Z")]), now: now, calendar: calendar)[0]
        XCTAssertEqual(TodayBoard.choice(for: "d", in: item)?.action, .answer(.deny))
        XCTAssertEqual(TodayBoard.choice(for: "A", in: item)?.action, .answer(.once))
        XCTAssertNil(TodayBoard.choice(for: "z", in: item))
    }

    func testStepsThroughTheItemsStoppingAtEitherEnd() {
        let sources = TodaySources(held: [held("a", at: "2026-11-01T10:00:00Z"), held("b", at: "2026-11-01T11:00:00Z")])
        let items = TodayBoard.overview(sources, now: now, calendar: calendar)
        XCTAssertEqual(TodayBoard.step(from: nil, by: 1, in: items), "held:a")
        XCTAssertEqual(TodayBoard.step(from: "held:a", by: 1, in: items), "held:b")
        XCTAssertEqual(TodayBoard.step(from: "held:b", by: 1, in: items), "held:b")
        XCTAssertEqual(TodayBoard.step(from: "held:a", by: -1, in: items), "held:a")
        XCTAssertEqual(TodayLines.position(of: "held:b", in: items), "2 of 2")
    }

    func testDoneHoldsWhatRanTodayAndTheLogHoldsEverything() throws {
        let activity = try rows("[" + [row("ok", at: "2026-11-01T09:00:00Z", effect: "allow"),
                                       row("broke", at: "2026-11-01T10:00:00Z", effect: "allow", failed: 1),
                                       row("asked", at: "2026-11-01T11:00:00Z", effect: "ask", answeredBy: "Moise"),
                                       row("old", at: "2026-10-31T09:00:00Z", effect: "allow")].joined(separator: ",") + "]")
        XCTAssertEqual(TodayBoard.done(activity, now: now, calendar: calendar).map(\.id), ["row:ok"])
        let log = TodayBoard.log(activity, now: now, calendar: calendar)
        XCTAssertEqual(log.map(\.id), ["row:asked", "row:broke", "row:ok"])
        XCTAssertEqual(log.map(\.state), [.done, .stopped, .done])
    }

    func testHandoffsAreWhatAgentsHandedBack() {
        let back = SessionCard(sessionId: "b", agentName: "Codex", task: "docs", state: "open")
        let working = SessionCard(sessionId: "w", agentName: "Codex", task: "tests", state: "working")
        XCTAssertEqual(TodayBoard.handoffs(TodaySources(sessions: [back, working])).map(\.id), ["session:b"])
    }

    func testWritesTheHeadlineAndTheStripFromCounts() {
        XCTAssertEqual(TodayLines.headline(now, needYou: 13, next: 1, openProjects: 7, calendar: calendar),
                       "1 Nov. 13 need you, 1 next, 7 open projects")
        XCTAssertEqual(TodayLines.headline(now, needYou: 1, next: 0, openProjects: 1, calendar: calendar),
                       "1 Nov. 1 needs you, 0 next, 1 open project")
        XCTAssertEqual(TodayLines.strip(needYou: 13, shown: TodayBoard.urgentShown), "13 need you, the 5 most urgent here")
        XCTAssertEqual(TodayLines.strip(needYou: 3, shown: 3), "3 need you")
        XCTAssertEqual(TodayLines.strip(needYou: 0, shown: 0), "Nothing needs you")
        XCTAssertEqual(TodayLines.synced(now, calendar: calendar), "synced 13:14")
    }

    func testAgesReadShortForTheColumn() {
        XCTAssertEqual(TodayLines.age(now.addingTimeInterval(-5), now: now), "now")
        XCTAssertEqual(TodayLines.age(now.addingTimeInterval(-20), now: now), "20 s")
        XCTAssertEqual(TodayLines.age(now.addingTimeInterval(-300), now: now), "5 min")
        XCTAssertEqual(TodayLines.age(now.addingTimeInterval(-7_200), now: now), "2 h")
        XCTAssertNil(TodayLines.age(nil, now: now))
        XCTAssertEqual(TodayLines.waited(nil, now: now), "Not recorded")
    }

    func testCountsOpenProjectsByRepositoryWithASessionStillOpen() {
        let cards = [SessionCard(sessionId: "a", agentName: "A", state: "working", repository: "memnox"),
                     SessionCard(sessionId: "b", agentName: "B", state: "open", repository: "memnox"),
                     SessionCard(sessionId: "c", agentName: "C", state: "ended", repository: "site")]
        XCTAssertEqual(TodayLines.openProjects(cards), 1)
    }
}
