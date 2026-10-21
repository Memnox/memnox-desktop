import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The tools offered before anybody searches: every one has a name, and none already connected is offered again.
final class FeaturedToolkitsTests: XCTestCase {
    func testOffersEveryOneToSomebodyWithNothingConnected() {
        XCTAssertEqual(FeaturedToolkits.suggested(excluding: []), FeaturedToolkits.slugs)
    }

    func testLeavesOutWhatIsConnectedAndKeepsTheOrder() {
        let connected = [ToolConnection(toolkit: "gmail", connected: true), ToolConnection(toolkit: "slack", connected: false)]
        let offered = FeaturedToolkits.suggested(excluding: connected)
        XCTAssertFalse(offered.contains("gmail"))
        XCTAssertFalse(offered.contains("slack"))
        XCTAssertEqual(offered.first, "googlecalendar")
    }

    func testNamesEveryFeaturedToolAsItCallsItself() {
        XCTAssertEqual(FeaturedToolkits.slugs.map(ToolkitName.of), [
            "Gmail", "Google Calendar", "Google Docs", "Google Drive", "Outlook", "Notion",
            "Slack", "GitHub", "Linear", "Jira",
        ])
    }
}
