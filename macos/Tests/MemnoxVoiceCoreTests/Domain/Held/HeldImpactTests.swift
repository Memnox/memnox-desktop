import XCTest

@testable import MemnoxVoiceCore

/// The impact is read as the cloud's `readHeldImpact` reads it: whole or not at all, bounded, and never in the way of the call.
final class HeldImpactTests: XCTestCase {
    private func claim(_ text: String, _ basis: String = "recorded", _ source: String = "git status") -> String {
        #"{"text":"\#(text)","basis":"\#(basis)","source":"\#(source)"}"#
    }

    private func call(impact: String?) throws -> WorkspaceHeldCall {
        let field = impact.map { #","impact":\#($0)"# } ?? ""
        let json = #"{"id":"hc_1","machineId":"m","agent":"codex","operation":"git.push","reason":"held"\#(field)}"#
        return try JSONDecoder().decode(WorkspaceHeldCall.self, from: Data(json.utf8))
    }

    private func impact(affected: String? = nil, undo: String? = nil, verified: String? = nil) -> String {
        let affected = affected ?? claim("Pushes three commits to main.")
        let undo = undo ?? claim("Only by another push.", "inferred", "")
        let verified = verified ?? "[\(claim("Tests passed.", "extracted", "ci log")),\(claim("Branch is clean."))]"
        return #"{"affected":\#(affected),"undo":\#(undo),"verified":\#(verified)}"#
    }

    func testAnOlderRuntimeSendsNoneAndTheCallIsStillRead() throws {
        let read = try call(impact: nil)
        XCTAssertEqual(read.id, "hc_1")
        XCTAssertNil(read.impact)
    }

    func testReadsTheThreeLinesInTheMachinesOwnWords() throws {
        let read = try XCTUnwrap(try call(impact: impact()).impact)
        XCTAssertEqual(read.lines.map(\.label), ["What could be affected", "Can it be undone?", "What has been verified"])
        XCTAssertEqual(read.lines.map(\.text), ["Pushes three commits to main.", "Only by another push.", "Tests passed. Branch is clean."])
    }

    func testDropsTheWholeImpactWhereAffectedOrUndoCannotBeRead() throws {
        XCTAssertNil(try call(impact: #"{"undo":\#(claim("x")),"verified":[]}"#).impact)
        XCTAssertNil(try call(impact: impact(undo: claim("x", "guessed"))).impact)
        XCTAssertNil(try call(impact: impact(affected: claim("   "))).impact)
        XCTAssertNil(try call(impact: impact(verified: #""none""#)).impact)
        XCTAssertNil(try call(impact: #""impact""#).impact)
    }

    func testDropsOnlyAVerifiedClaimThatCannotBeRead() throws {
        let read = try XCTUnwrap(try call(impact: impact(verified: "[\(claim("ok")),\(claim("bad", "maybe")),7]")).impact)
        XCTAssertEqual(read.verified, [HeldClaim(text: "ok", basis: .recorded, source: "git status")])
    }

    func testIsBoundedByLengthAndByCount() throws {
        let long = "  " + String(repeating: "a", count: 400) + "  "
        let many = "[" + (0..<12).map { claim("v\($0)") }.joined(separator: ",") + "]"
        let read = try XCTUnwrap(try call(impact: impact(affected: #"{"text":"\#(long)","basis":"recorded","source":7}"#, verified: many)).impact)
        XCTAssertEqual(read.affected.text.count, 300)
        XCTAssertEqual(read.affected.source, "")
        XCTAssertEqual(read.verified.count, 8)
    }

    func testSaysHowEachClaimIsKnownOnlyForTheDisclosure() throws {
        let read = try XCTUnwrap(try call(impact: impact()).impact)
        XCTAssertEqual(read.evidence.map(\.label), ["recorded", "inferred, not checked", "extracted", "recorded"])
        XCTAssertEqual(read.evidence.map(\.value), ["Pushes three commits to main. (git status)", "Only by another push.",
                                                     "Tests passed. (ci log)", "Branch is clean. (git status)"])
        XCTAssertEqual(ClaimBasis.unknown.words, "not established")
    }
}
