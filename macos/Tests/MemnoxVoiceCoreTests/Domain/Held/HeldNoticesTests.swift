import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/held-notices.test.ts, so a held call is said alike on every desktop.
final class HeldNoticesTests: XCTestCase {
    private let push = NoticeCall(subject: "a", label: "Claude Code", what: "git push origin main")
    private let pushAgain = NoticeCall(subject: "b", label: "Claude Code", what: "git push origin main")
    private let deploy = NoticeCall(subject: "c", label: "Codex", what: "npm run deploy")

    func testSaysWhoWaitsAndOnWhat() {
        let notice = HeldNotice(push)
        XCTAssertEqual(notice.subject, "a")
        XCTAssertEqual(notice.title, "Claude Code is waiting on you")
        XCTAssertEqual(notice.body, "git push origin main")
    }

    func testPostsOneNotificationPerCallAndNoneForACallToldAgain() {
        var notices = HeldNotices()
        XCTAssertEqual(notices.next([push], onIsland: nil).map(\.subject), ["a"])
        XCTAssertEqual(notices.next([push], onIsland: nil), [])
        XCTAssertEqual(notices.next([push, deploy], onIsland: nil).map(\.subject), ["c"])
    }

    func testFoldsAnIdenticalHoldIntoTheOneAlreadySaid() {
        var notices = HeldNotices()
        _ = notices.next([push], onIsland: nil)
        XCTAssertEqual(notices.next([push, pushAgain], onIsland: nil), [])
    }

    func testSaysNothingForTheCallTheIslandShowsAndFoldsItsTwinsIntoIt() {
        var notices = HeldNotices()
        XCTAssertEqual(notices.next([push], onIsland: "a"), [])
        XCTAssertEqual(notices.next([push, pushAgain], onIsland: "a"), [])
        XCTAssertEqual(notices.next([push, pushAgain, deploy], onIsland: "a").map(\.subject), ["c"])
    }

    func testSaysTheSameHoldAgainOnceEveryCallOfItStoppedWaiting() {
        var notices = HeldNotices()
        _ = notices.next([push], onIsland: nil)
        _ = notices.next([], onIsland: nil)
        XCTAssertEqual(notices.next([pushAgain], onIsland: nil).map(\.subject), ["b"])
    }

    func testOpensNeedsYouWhereTheCallWaits() {
        XCTAssertEqual(HeldNotices.opens, WindowRoute(.needsYou, tab: "decide-now"))
    }
}
