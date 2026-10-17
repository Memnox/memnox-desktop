import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// One id source for every use case, since a relay session refuses a request whose id is already in flight.
final class RequestIdsTests: XCTestCase {
    func testCountsUpFromOne() {
        let ids = RequestIds()
        XCTAssertEqual([ids.next(), ids.next(), ids.next()], [1, 2, 3])
    }

    func testTheConversationThePairingAndASubscriptionNeverShareAnId() async {
        let link = ScriptedLink()
        let ids = RequestIds()
        let conversation = Conversation(link: link, speaker: RecordingSpeaker(), key: PersonKey(), face: RecordingFace(),
                                        owner: MemoryOwner(nil), ids: ids)
        let pairing = Pairing(link: link, key: PersonKey(), ids: ids)
        _ = await conversation.sessionsList()
        _ = await pairing.devices()
        _ = try? await link.request(DaemonRequest(id: ids.next(), method: .subscribe))
        _ = await conversation.sessionView("s1")
        _ = await pairing.tellVoice("af_heart")

        let sent = link.sent.map(\.id)
        XCTAssertEqual(sent, [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(sent).count, sent.count)
    }

    func testIdsTakenFromManyThreadsAtOnceAreAllDifferent() async {
        let ids = RequestIds()
        let taken = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<200 { group.addTask { ids.next() } }
            var all: [Int] = []
            for await id in group { all.append(id) }
            return all
        }
        XCTAssertEqual(Set(taken).count, 200)
    }
}
