import XCTest

@testable import MemnoxVoiceCore

/// The Layers view's words: three numbered cards, a value line only where a number was measured, the short term card
/// with money only where every model was priced, and a line diff that keeps order.
final class MemoryLayersLinesTests: XCTestCase {
    private func project(index: MemoryIndexLayerView, routers: [MemoryRouterLayerView] = [],
                         skills: [MemorySkillLayerView] = []) -> ProjectLayersView {
        ProjectLayersView(name: "acme", path: "/r/acme", agents: ["claude-code"], index: index, routers: routers,
                          skills: skills, keep: [])
    }

    func testNumbersTheThreeLayersAndSaysHowEachStands() {
        let cards = MemoryLayersLines.cards(project(
            index: MemoryIndexLayerView(path: "MEMORY.md", present: true, lines: 12, unlinked: 3),
            routers: [MemoryRouterLayerView(agent: "claude-code", path: "CLAUDE.md", present: true, lines: 40, chars: 900,
                                            departments: ["macos", "linux"], routed: 1)],
            skills: [MemorySkillLayerView(name: "orders", path: ".claude/skills/orders/SKILL.md", liveData: true)]))
        XCTAssertEqual(cards.map(\.number), [1, 2, 3])
        XCTAssertEqual(cards.map(\.role), ["every chat", "the router", "live data"])
        XCTAssertEqual(cards[0].state, "12 lines, 3 lines linked to no file")
        XCTAssertEqual(cards[1].state, "Routes 1 of 2 departments")
        XCTAssertEqual(cards[2].state, "1 skill, 1 say where live data is")
        XCTAssertEqual(cards.map(\.settled), [false, false, true])
    }

    func testSaysALayerNotWrittenYetRatherThanAnEmptyNumber() {
        let cards = MemoryLayersLines.cards(project(index: MemoryIndexLayerView(path: "MEMORY.md", present: false, lines: 0, unlinked: 0)))
        XCTAssertEqual(cards[0].state, "Not written yet")
        XCTAssertEqual(cards[1].file, "CLAUDE.md")
        XCTAssertEqual(cards[2].state, "No SKILL.md in this project")
    }

    func testDrawsTheValueLineOnlyWithMeasuredNumbers() {
        XCTAssertEqual(MemoryLayersLines.value(nil), [])
        XCTAssertEqual(MemoryLayersLines.value(MemoryValueView()), [])
        let lines = MemoryLayersLines.value(MemoryValueView(searchMedianMs: 11.6, searches: 40, contextTokensSaved: 12_500))
        XCTAssertEqual(lines.map(\.title), ["Faster to find", "Cheaper to find"])
        XCTAssertEqual(lines[0].figure, "12 ms")
        XCTAssertEqual(lines[0].detail, "median over the last 40 searches")
        XCTAssertEqual(lines[1].figure, "12,500 tokens")
    }

    func testCountsColdReloadsAndGivesMoneyOnlyWherePriced() {
        let priced = SessionCostView(days: 30, sessions: 4, turns: 90, coldReloads: 3, reloadedTokens: 1_200_000,
                                     reloadCostUsd: 6, warmSavingUsd: 4.25, warmHours: 4)
        XCTAssertEqual(MemoryLayersLines.sessionCost(priced), [
            "3 cold reloads in 30 days, over 4 chats",
            "1,200,000 tokens written into the cache again",
            "Reloading cost $6.00 at API prices",
            "Keeping chats warm 4h would have saved $4.25",
        ])
        let unpriced = SessionCostView(days: 30, sessions: 1, turns: 2, coldReloads: 1, reloadedTokens: 10,
                                       warmHours: 4, unpricedModels: ["mystery"])
        XCTAssertEqual(MemoryLayersLines.sessionCost(unpriced).last, "No price is known for mystery, so no total is given")
        let losing = SessionCostView(days: 30, sessions: 1, turns: 2, coldReloads: 1, reloadedTokens: 10,
                                     reloadCostUsd: 0.01, warmSavingUsd: -0.5, warmHours: 4)
        XCTAssertEqual(MemoryLayersLines.sessionCost(losing).last, "Keeping chats warm 4h would have cost more than it saved")
    }

    func testDiffsBeforeAndAfterInOrder() {
        let diff = MemoryLayersLines.diff(before: ["a", "b", "c"], after: ["a", "c", "d"])
        XCTAssertEqual(diff.map(\.mark), [.same, .removed, .same, .added])
        XCTAssertEqual(diff.map(\.text), ["a", "b", "c", "d"])
        XCTAssertEqual(MemoryLayersLines.diff(before: [], after: ["x"]).map(\.mark), [.added])
    }

    func testSaysWhatConfirmingWouldWrite() {
        let file = { (changed: Bool) in
            MemoryLayerFilePlan(path: "MEMORY.md", layer: .index, whole: false, before: [], after: [], changed: changed)
        }
        XCTAssertEqual(MemoryLayersLines.planSummary(MemoryLayersPlan(project: "/r", digest: "d", files: [file(false)])),
                       "Everything is already as the map would write it.")
        XCTAssertEqual(MemoryLayersLines.planSummary(MemoryLayersPlan(project: "/r", digest: "d", files: [file(true), file(false)])),
                       "Writes 1 file, 1 already as planned. Only what sits inside Memnox's fenced blocks changes.")
        XCTAssertEqual(MemoryLayersLines.keepList(" the release branch\n\n  tests first "), ["the release branch", "tests first"])
    }
}
