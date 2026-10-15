import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// An agent's own question read off the daemon, and which of its questions the island asks next.
final class AgentQuestionTests: XCTestCase {
    private let asked = #"""
    {"kind":"notice","notice":"question","subject":"aqn_1","agent":"claude-code","agentName":"Claude Code",
     "summary":"Claude Code is asking you: What should the island look like?","at":"2026-10-15T00:00:00Z",
     "questions":[
       {"question":"What should the island look like?","header":"Island",
        "options":[{"label":"Mark in the island","description":"a mark and a count"},{"label":"Real orb, larger"}],
        "multiSelect":false},
       {"question":"Where should it notify?","options":[{"label":"Mac"},{"label":"iPhone"},{"label":"Watch"}],"multiSelect":true}
     ]}
    """#

    func testReadsTheQuestionsWithTheirChoices() throws {
        let questions = try XCTUnwrap(event(asked).questions)
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions[0].header, "Island")
        XCTAssertEqual(questions[0].options[0], AgentQuestionOption(label: "Mark in the island", description: "a mark and a count"))
        XCTAssertNil(questions[0].options[1].description)
        XCTAssertTrue(questions[1].multiSelect)
    }

    func testToleratesAQuestionWithItsOptionalFieldsLeftOut() throws {
        let bare = try event(#"{"kind":"notice","notice":"question","subject":"aqn_2","agent":"a","summary":"s","at":"t","questions":[{"question":"Which?"}]}"#)
        let item = try XCTUnwrap(bare.questions?.first)
        XCTAssertEqual(item.options, [])
        XCTAssertFalse(item.multiSelect)
    }

    func testAnOlderDaemonsQuestionStaysSpokenOnly() throws {
        let older = try event(#"{"kind":"notice","notice":"question","subject":"aqn_3","agent":"a","summary":"s","at":"t"}"#)
        XCTAssertNil(AgentQuestionCard(older))
        let finished = try event(#"{"kind":"notice","notice":"finished","subject":"ntc_1","agent":"a","summary":"s","at":"t","questions":[{"question":"Which?"}]}"#)
        XCTAssertNil(AgentQuestionCard(finished))
    }

    func testAsksTheFirstQuestionStillOpenAndMovesOnOnceItIsAnswered() throws {
        let card = try XCTUnwrap(AgentQuestionCard(event(asked)))
        XCTAssertEqual(card.who, "Claude Code")
        XCTAssertEqual(card.next?.number, 1)
        XCTAssertEqual(card.position, "1 of 2")
        let moved = card.answering(1, with: "Mark in the island")
        XCTAssertEqual(moved.next?.number, 2)
        XCTAssertEqual(moved.position, "2 of 2")
        XCTAssertNil(moved.answering(2, with: "Mac").next)
    }

    func testSkipsWhatTheDaemonSaysIsAlreadyPicked() throws {
        let partly = asked.replacingOccurrences(
            of: #""at":"2026-10-15T00:00:00Z","#,
            with: #""at":"2026-10-15T00:00:00Z","answers":{"What should the island look like?":"Real orb, larger"},"#
        )
        let card = try XCTUnwrap(AgentQuestionCard(event(partly)))
        XCTAssertEqual(card.next?.item.question, "Where should it notify?")
    }

    func testJoinsSeveralPicksInTheOrderTheAgentListedThem() throws {
        let item = try XCTUnwrap(event(asked).questions?[1])
        XCTAssertEqual(AgentQuestionCard.joined(["Watch", "Mac"], from: item), "Mac, Watch")
    }
}
