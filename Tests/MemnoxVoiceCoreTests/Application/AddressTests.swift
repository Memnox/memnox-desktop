import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The address the composition root reads, used and never guessed.
final class AddressTests: XCTestCase {
    func testGreetsByTheAddressTheCompositionRootReadsAndByNoneWithoutOne() {
        func greeting(_ address: String?) -> String {
            let conversation = Conversation(
                link: ScriptedLink(), speaker: RecordingSpeaker(), key: PersonKey(), face: RecordingFace(),
                owner: MemoryOwner(nil), address: { address }
            )
            return conversation.answerToCall()
        }
        XCTAssertTrue(greeting("sir").contains("sir"))
        // Only the greeting's own sentence, since a line such as "Your agents, your rules." carries a comma of its own.
        let firstSentence = greeting(nil).prefix { $0 != "." }
        XCTAssertFalse(firstSentence.contains(","))
    }
}
