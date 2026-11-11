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

        let pages: [Page]
        let groups: [String: String]
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
}
