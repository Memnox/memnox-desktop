@testable import MemnoxVoiceCore
import XCTest

final class AgentCheckTextTests: XCTestCase {
    private func agent(works: Bool?, because: String? = nil, reply: String? = nil, chosen: Bool = false, sealed: Bool = true) -> VoiceAgentStatus {
        VoiceAgentStatus(kind: "cursor", label: "Cursor", installed: true, sealed: sealed, works: works,
                         because: because, reply: reply, chosen: chosen)
    }

    func testAReplyIsQuotedApartFromAShortStatus() {
        let spent = agent(works: false, because: "its own account replied \"Upgrade your plan\", so it cannot be the voice yet",
                          reply: "Upgrade your plan")

        XCTAssertEqual(AgentCheckText.status(spent, checking: false), "Its own account answered in place of Memnox")
        XCTAssertEqual(AgentCheckText.reply(spent), "Upgrade your plan")
        XCTAssertTrue(AgentCheckText.notReady(spent))
    }

    func testAReasonWithoutAReplyStartsWithACapital() {
        let late = agent(works: false, because: "no answer within 90 seconds")

        XCTAssertEqual(AgentCheckText.status(late, checking: false), "No answer within 90 seconds")
        XCTAssertNil(AgentCheckText.reply(late))
    }

    func testAWorkingAgentSaysWhetherItIsTheOne() {
        XCTAssertEqual(AgentCheckText.status(agent(works: true), checking: false), "Ready to answer")
        XCTAssertEqual(AgentCheckText.status(agent(works: true, chosen: true), checking: false), "Answers when you talk, kept to reading")
        XCTAssertNil(AgentCheckText.reply(agent(works: true, reply: "memnox ready")))
    }

    func testAnUnaskedAgentSaysWhetherItIsBeingAsked() {
        XCTAssertEqual(AgentCheckText.status(agent(works: nil), checking: true), "Asking it one question")
        XCTAssertEqual(AgentCheckText.status(agent(works: nil), checking: false), "Not asked yet")
        XCTAssertFalse(AgentCheckText.notReady(agent(works: nil)))
    }

    func testNamesReadAsASentence() {
        XCTAssertEqual(AgentCheckText.names(["Cursor"]), "Cursor")
        XCTAssertEqual(AgentCheckText.names(["Cursor", "Hermes"]), "Cursor and Hermes")
        XCTAssertEqual(AgentCheckText.names(["Codex", "Cursor", "Hermes"]), "Codex, Cursor and Hermes")
    }
}
