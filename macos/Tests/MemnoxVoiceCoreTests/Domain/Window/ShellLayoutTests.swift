import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/shell-layout.test.ts: the shell at each breakpoint the window is checked at.
final class ShellLayoutTests: XCTestCase {
    func testKeepsTheInspectorBesideThePageAt1280() {
        XCTAssertEqual(WidthClass(width: 1280), .wide)
        XCTAssertEqual(ShellLayout(WidthClass(width: 1280), collapsed: false), ShellLayout(sidebar: .labels, inspector: .beside, canFold: true))
        XCTAssertEqual(ShellLayout(WidthClass(width: 1280), collapsed: true).sidebar, .rail)
    }

    func testFloatsTheInspectorAsADrawerAt1000() {
        XCTAssertEqual(WidthClass(width: 1000), .medium)
        XCTAssertEqual(ShellLayout(WidthClass(width: 1000), collapsed: false), ShellLayout(sidebar: .labels, inspector: .drawer, canFold: true))
    }

    func testFoldsTheSidebarToIconsAt760() {
        XCTAssertEqual(WidthClass(width: 760), .narrow)
        XCTAssertEqual(ShellLayout(WidthClass(width: 760), collapsed: false), ShellLayout(sidebar: .rail, inspector: .full, canFold: false))
    }

    func testTurnsTheSidebarIntoASheetAt480() {
        XCTAssertEqual(WidthClass(width: 480), .compact)
        XCTAssertEqual(ShellLayout(WidthClass(width: 480), collapsed: true), ShellLayout(sidebar: .sheet, inspector: .full, canFold: false))
    }

    func testThePaletteListsTheNumberKeyBesideEachDestination() {
        let keyed = Destinations.commands { _ in true }.compactMap { each in each.key.map { "\($0) \(each.title)" } }
        XCTAssertEqual(keyed, ["1 Home", "2 Agents", "3 Workspaces", "4 MCP Hub", "5 Governance"])
    }
}
