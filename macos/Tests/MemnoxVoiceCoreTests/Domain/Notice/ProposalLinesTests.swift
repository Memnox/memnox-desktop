import XCTest
@testable import MemnoxVoiceCore

/// A proposal worded by its kind on the island, at Touch ID and when declined, and in its own words when no kind came.
final class ProposalLinesTests: XCTestCase {
    func testPutsTheKindBeforeItsOwnWordsAtTouchID() {
        XCTAssertEqual(ProposalLines.prompt(kind: "mcp-hub", summary: "Add the MCP server github"),
                       "A change to your MCP servers: Add the MCP server github")
        XCTAssertEqual(ProposalLines.caption(kind: "lan", summary: "Let paired phones in"),
                       "Touch ID for opening this Mac to your local network")
    }

    func testNamesTheKindItDeclined() {
        XCTAssertEqual(ProposalLines.unasked(kind: "skills-hub"),
                       "Something proposed a change to your skills, which you did not ask for. I have declined it.")
    }

    func testFallsBackToItsOwnWordsFromAnOlderDaemonOrAnUnknownKind() {
        XCTAssertEqual(ProposalLines.prompt(kind: nil, summary: "keep GITHUB_TOKEN"), "keep GITHUB_TOKEN")
        XCTAssertEqual(ProposalLines.prompt(kind: "something-new", summary: "keep GITHUB_TOKEN"), "keep GITHUB_TOKEN")
        XCTAssertEqual(ProposalLines.caption(kind: nil, summary: "keep GITHUB_TOKEN"), "Touch ID to keep GITHUB_TOKEN")
        XCTAssertEqual(ProposalLines.unasked(kind: nil), ProposalLines.unaskedAllow)
        XCTAssertEqual(ProposalLines.unasked(kind: "something-new"), ProposalLines.unaskedAllow)
    }

    func testTheIslandDeclinesAnUnaskedProposalInItsKindsWords() async throws {
        let link = ScriptedLink()
        link.answers["confirm"] = [try line(#"{"id":9,"ok":true}"#)]
        let speaker = RecordingSpeaker()
        let conversation = Conversation(link: link, speaker: speaker, key: PersonKey(), face: RecordingFace(),
                                        owner: MemoryOwner(nil))
        let proposal = #"{"kind":"proposal","subject":"prp_1","agent":"agt_memnox-hub","summary":"Add the MCP server github","at":"2026-10-06T00:00:00Z","proposalKind":"mcp-hub"}"#

        await conversation.handle(try event(proposal))

        XCTAssertEqual(speaker.said, [ProposalLines.unasked(kind: "mcp-hub")])
    }
}
