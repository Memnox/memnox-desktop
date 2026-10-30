import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/live-activity.test.ts, so the Mac shows rows as they arrive the way Windows and Linux do.
final class LiveActivityTests: XCTestCase {
    private static func live(_ id: String, effect: String = "allow", agent: String = "claude-code") -> LiveActivityRow {
        LiveActivityRow(id: id, at: "2026-10-30T10:00:00Z", agent: agent, operation: "git.push", effect: effect, target: "origin")
    }

    private func activityOn(_ filter: ActivityFilter = ActivityFilter()) async throws -> Activity {
        let link = ScriptedLink()
        let row = #"{"id":"old","at":"2026-10-30T09:00:00Z","agent":"claude-code","agentName":"Claude Code","session":"s","kind":"command","operation":"git.push","effect":"allow","reason":"allowed"}"#
        link.answers["activity"] = [try line(#"{"id":1,"ok":true,"activity":{"rows":["# + row + #"],"nextCursor":"c1"}}"#)]
        let activity = Activity(link: link)
        await activity.show(filter)
        return activity
    }

    func testShowsLeavesOutOrLeavesToARefreshWhatNamesAloneCannotTell() {
        let row = Self.live("a")
        XCTAssertEqual(LiveActivityLines.match(row, ActivityFilter()), .shown)
        XCTAssertEqual(LiveActivityLines.match(row, ActivityFilter(effect: .deny)), .hidden)
        XCTAssertEqual(LiveActivityLines.match(row, ActivityFilter(agent: "codex-cli")), .hidden)
        XCTAssertEqual(LiveActivityLines.match(row, ActivityFilter(text: "ORIGIN")), .shown)
        XCTAssertEqual(LiveActivityLines.match(row, ActivityFilter(text: "deploy")), .hidden)
        XCTAssertEqual(LiveActivityLines.match(row, ActivityFilter(since: "2026-10-31T00:00:00Z")), .hidden)
        XCTAssertEqual(LiveActivityLines.match(row, ActivityFilter(kind: .command)), .unknown)
    }

    func testWordsThePillAndTheRefreshLine() {
        XCTAssertEqual(LiveActivityLines.newRows(3), "3 new")
        XCTAssertEqual(LiveActivityLines.missedRows(4), "and 4 more, refresh to see them")
    }

    func testPutsMatchingRowsAboveTheFirstPageNewestFirst() async throws {
        let activity = try await activityOn(ActivityFilter(effect: .allow))
        activity.heard([Self.live("a"), Self.live("b"), Self.live("c", effect: "deny")], missed: 0)
        XCTAssertEqual(activity.live.map(\.id), ["b", "a"])
        XCTAssertEqual(activity.rows.map(\.id), ["old"])
        XCTAssertTrue(activity.more)
    }

    func testHoldsRowsBehindThePillWhileScrolledAway() async throws {
        let activity = try await activityOn()
        activity.atTop(false)
        activity.heard([Self.live("a"), Self.live("b")], missed: 0)
        XCTAssertEqual(activity.live, [])
        XCTAssertEqual(activity.waiting, 2)
        activity.showWaiting()
        XCTAssertEqual(activity.live.map(\.id), ["b", "a"])
        activity.heard([Self.live("c")], missed: 0)
        activity.atTop(true)
        XCTAssertEqual(activity.live.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(activity.waiting, 0)
    }

    func testCountsWhatABurstDidNotCarryAndForgetsItOnARefresh() async throws {
        let activity = try await activityOn(ActivityFilter(kind: .command))
        activity.heard([Self.live("a")], missed: 5)
        XCTAssertEqual(activity.live, [])
        XCTAssertEqual(activity.missed, 6)
        await activity.show(ActivityFilter())
        XCTAssertEqual(activity.missed, 0)
    }

    func testNeverShowsARowTwiceAndKeepsTheLiveRowsBounded() async throws {
        let activity = try await activityOn()
        activity.heard([Self.live("old"), Self.live("a")], missed: 0)
        activity.heard([Self.live("a")], missed: 0)
        XCTAssertEqual(activity.live.map(\.id), ["a"])
        activity.heard((0..<(LiveActivityLines.mostKept + 3)).map { Self.live("n\($0)") }, missed: 0)
        XCTAssertEqual(activity.live.count, LiveActivityLines.mostKept)
        XCTAssertEqual(activity.missed, 4)
    }

    func testReadsTheEventAndIsNeverSaid() throws {
        let heard = try event(#"{"kind":"activity","subject":"a","agent":"claude-code","summary":"2 actions","at":"t","activityRows":[{"id":"a","at":"t","agent":"claude-code","operation":"git.push","effect":"allow"}],"activityMissed":3}"#)
        XCTAssertEqual(heard.eventKind, .activity)
        XCTAssertEqual(heard.activityRows?.map(\.id), ["a"])
        XCTAssertEqual(heard.activityMissed, 3)
        XCTAssertTrue(heard.isShownOnly)
        XCTAssertFalse(heard.isSaid(speakUp: true))
        XCTAssertFalse(heard.awaitsAnswer)
        XCTAssertFalse(MachineEvents.delivers(heard, chosen: false, thisMac: true))
    }

    func testCountsLiveActionsIntoTodayOnHome() {
        let home = DaemonHome(machine: "m", mode: "enforce", waiting: 0, working: [],
                              today: HomeToday(actions: 4, asked: 1, allowed: 2, refused: 0),
                              notCovered: HomeNotCovered(unprotected: 0, dormant: 0))
        XCTAssertEqual(home.counting(actions: 3).today, HomeToday(actions: 7, asked: 1, allowed: 2, refused: 0))
        XCTAssertEqual(home.counting(actions: 0), home)
    }
}
