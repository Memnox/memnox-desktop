import XCTest

@testable import MemnoxVoiceCore

/// A session's issue reads the same here as in the console: linked, not verified, or ambiguous, and nothing else.
/// Mirrors shared/tauri-core/test/work-correlations.test.ts.
final class WorkCorrelationsTests: XCTestCase {
    private static let item = #""item":{"provider":"jira","label":"PAY-42","url":"https://acme.atlassian.net/browse/PAY-42"}"#

    private func row(id: String = "wcr_1", session: String = "ses_1", source: String = "branch", state: String = "linked",
                     claim: String? = "PAY-42", visible: Bool = true, extra: String = "") -> String {
        let claimed = claim.map { #","claim":"\#($0)""# } ?? ""
        let more = extra.isEmpty ? "" : ",\(extra)"
        return #"{"id":"\#(id)","sessionId":"\#(session)","source":"\#(source)","state":"\#(state)","lateMatch":false,"visible":\#(visible)\#(claimed)\#(more)}"#
    }

    private func read(_ rows: [String]) throws -> [WorkCorrelation] {
        let body = #"{"correlations":[\#(rows.joined(separator: ","))]}"#
        return try JSONDecoder().decode(WorkCorrelations.self, from: Data(body.utf8)).correlations
    }

    func testReadsEachRowOnItsOwnAndDropsOneItCannotRead() throws {
        let all = try read([row(extra: Self.item), #"{"id":3}"#])
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.item?.label, "PAY-42")
        XCTAssertEqual(try JSONDecoder().decode(WorkCorrelations.self, from: Data("{}".utf8)).correlations, [])
    }

    func testSaysWhatALinkRestsOnAndWhyAClaimIsNotLinked() throws {
        let linked = try XCTUnwrap(read([row(extra: Self.item)]).first)
        let waiting = try XCTUnwrap(read([row(state: "pending")]).first)
        let split = try XCTUnwrap(read([row(state: "ambiguous", extra: #""matches":2"#)]).first)
        XCTAssertEqual(WorkCorrelationLines.label(linked), "PAY-42")
        XCTAssertEqual(WorkCorrelationLines.reason(linked), "Linked via branch")
        XCTAssertEqual(WorkCorrelationLines.link(linked)?.host, "acme.atlassian.net")
        XCTAssertEqual(WorkCorrelationLines.label(waiting), "PAY-42, not verified")
        XCTAssertEqual(WorkCorrelationLines.reason(waiting), "Waiting for the tracker to deliver it.")
        XCTAssertNil(WorkCorrelationLines.link(waiting))
        XCTAssertEqual(WorkCorrelationLines.label(split), "PAY-42 matches 2 trackers, not linked")
        XCTAssertNil(WorkCorrelationLines.reason(split))
        XCTAssertEqual(WorkCorrelationLines.via("provider_link"), "Linked via pull request")
        XCTAssertEqual(WorkCorrelationLines.via("something_new"), "Linked via something_new")
    }

    func testShowsAnItemTheReaderCannotSeeWithoutNamingIt() throws {
        let hidden = try XCTUnwrap(read([row(claim: nil, visible: false, extra: Self.item)]).first)
        XCTAssertEqual(WorkCorrelationLines.label(hidden), "An item you cannot see")
        XCTAssertNil(WorkCorrelationLines.link(hidden))
    }

    func testLeavesReplacedAndRemovedMatchesOutOnePerClaim() throws {
        let all = try read([row(), row(id: "wcr_2", source: "commit"), row(id: "wcr_3", state: "superseded", claim: "PAY-1"),
                            row(id: "wcr_4", session: "ses_2")])
        XCTAssertEqual(WorkCorrelationLines.forSession(all, "ses_1").map(\.id), ["wcr_1"])
        XCTAssertNil(WorkCorrelationLines.shown(all[2]))
    }

    func testKeepsEveryWordFreeOfDashes() {
        let words = [WorkCorrelationLines.heading, WorkCorrelationLines.hidden, WorkCorrelationLines.lateMatch, WorkCorrelationLines.explain,
                     WorkCorrelationLines.unverified("PAY-42"), WorkCorrelationLines.ambiguous("PAY-42", matches: 2)]
        for line in words {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }
}
