import XCTest

@testable import MemnoxVoiceCore

/// The window against `shared/ux/contract.json`, the verbatim copy of `memnox-runtime/docs/ux/contract.json` every
/// surface checks itself against, so this Mac cannot drift from the console, Windows, Linux and the phone unnoticed.
final class UxContractTests: XCTestCase {
    private struct Contract: Decodable {
        struct Tab: Decodable {
            let id: String
            let label: String
            let platforms: [String]?
        }

        struct Page: Decodable {
            let id: String
            let label: String
            let group: String?
            let sf: String
            let platforms: [String]
            let tabs: [Tab]?
            let views: [Tab]?
            let sections: [Tab]?
        }

        struct Answers: Decodable {
            let labels: [String: String]
            let outcomes: [String: String]
            let always: String
            let never: String
        }

        struct Statuses: Decodable {
            let order: [String]
            let labels: [String: String]
            let reasons: [String: String]
        }

        struct Care: Decodable {
            struct Level: Decodable {
                let label: String
                let line: String
                let mode: String
                let pack: String?
            }

            let order: [String]
            let recommended: String
            let levels: [String: Level]
        }

        struct Step: Decodable {
            let id: String
            let title: String
            let platforms: [String]?
        }

        let pages: [Page]
        let groups: [String: String]
        let careful: Care
        let onboarding: [Step]
        let modes: [String: String]
        let answers: Answers
        let sessionStatus: Statuses
    }

    private static let platform = "mac"

    /// Five folders up from this file is the desktop repository, where `shared/` sits beside `macos/`.
    private func contract() throws -> Contract {
        var here = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { here.deleteLastPathComponent() }
        let candidates = [
            here.appendingPathComponent("shared/ux/contract.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("../shared/ux/contract.json"),
        ]
        let found = try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0.path) }, "no shared/ux/contract.json")
        return try JSONDecoder().decode(Contract.self, from: Data(contentsOf: found))
    }

    func testListsThePagesOfTheContractInItsOrderWithItsWordsAndIcons() throws {
        let pages = try contract().pages.filter { $0.platforms.contains(Self.platform) }
        XCTAssertEqual(Destinations.all.map(\.id.rawValue), pages.map(\.id))
        XCTAssertEqual(Destinations.all.map(\.title), pages.map(\.label))
        XCTAssertEqual(Destinations.all.map(\.symbol), pages.map(\.sf))
        XCTAssertEqual(Destinations.all.map { $0.group == .top ? nil : $0.group.rawValue }, pages.map(\.group))
    }

    func testDrawsNeedsYousViewsAndSectionsInTheContractsWords() throws {
        let page = try XCTUnwrap(try contract().pages.first { $0.id == Destination.needsYou.rawValue })
        let views = (page.views ?? []).filter { $0.platforms?.contains(Self.platform) ?? true }
        XCTAssertEqual(NeedsYouView.allCases.map(\.rawValue), views.map(\.id))
        XCTAssertEqual(NeedsYouView.allCases.map(\.title), views.map(\.label))
        let sections = (page.sections ?? []).filter { $0.platforms?.contains(Self.platform) ?? true }
        XCTAssertEqual(sections.map(\.label), [TeamRuleChangeLines.title])
        let rules = try XCTUnwrap(try contract().pages.first { $0.id == Destination.rules.rawValue })
        XCTAssertEqual((rules.sections ?? []).filter { $0.platforms?.contains(Self.platform) ?? true }.map(\.label),
                       [RuleHistoryLines.title])
    }

    func testGivesEveryPageTheContractsTabsForThisMac() throws {
        for page in try contract().pages where page.platforms.contains(Self.platform) && page.id != Destination.settings.rawValue {
            let tabs = (page.tabs ?? []).filter { $0.platforms?.contains(Self.platform) ?? true }
            let mine = Destinations.info(try XCTUnwrap(Destination(rawValue: page.id))).tabs
            XCTAssertEqual(mine.map(\.id), tabs.map(\.id), page.id)
            XCTAssertEqual(mine.map(\.title), tabs.map(\.label), page.id)
        }
    }

    func testHeadsTheSectionsAsTheContractDoes() throws {
        let groups = try contract().groups
        XCTAssertEqual(SidebarGroup.govern.title, groups["govern"])
        XCTAssertEqual(SidebarGroup.knowledge.title, groups["knowledge"])
    }

    func testAnswersAndNamesSessionsInTheContractsWords() throws {
        let words = try contract()
        for answer in AnswerWords.order {
            XCTAssertEqual(AnswerWords.label(answer), words.answers.labels[answer.rawValue])
            XCTAssertEqual(AnswerWords.outcome(answer), words.answers.outcomes[answer.rawValue])
        }
        XCTAssertEqual(AnswerWords.order.last, .deny)
        XCTAssertEqual(AnswerWords.label(.always), words.answers.always)
        XCTAssertEqual(AnswerWords.alwaysDeny, words.answers.never)
        XCTAssertEqual(SessionStatus.allCases.map(\.rawValue), words.sessionStatus.order)
        for status in SessionStatus.allCases { XCTAssertEqual(status.label, words.sessionStatus.labels[status.rawValue]) }
        for reason in SessionReason.allCases { XCTAssertEqual(reason.label, words.sessionStatus.reasons[reason.rawValue]) }
    }

    func testOffersTheContractsLevelsOfCareInItsWords() throws {
        let care = try contract().careful
        XCTAssertEqual(CareLevel.allCases.map(\.rawValue), care.order)
        XCTAssertEqual(CareLevel.recommended.rawValue, care.recommended)
        for level in CareLevel.allCases {
            let written = try XCTUnwrap(care.levels[level.rawValue])
            XCTAssertEqual(level.label, written.label)
            XCTAssertEqual(level.line, written.line)
            XCTAssertEqual(level.enforces, written.mode == "enforce")
            XCTAssertEqual(level.packId, written.pack)
        }
    }

    func testTitlesTheFirstRunStepsAsTheContractDoes() throws {
        let steps = try contract().onboarding
        XCTAssertEqual(FirstRunStepID.connect.title, steps.first { $0.id == "agents" }?.title)
        XCTAssertEqual(FirstRunStepID.rules.title, steps.first { $0.id == "careful" }?.title)
    }

    func testNamesTheModesInTheContractsWords() throws {
        let modes = try contract().modes
        XCTAssertEqual(HomeMode.observe.badge, modes["observe"])
        XCTAssertEqual(HomeMode.enforce.badge, modes["enforce"])
    }
}
