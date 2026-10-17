import XCTest
@testable import MemnoxVoiceCore

final class HistoryFileTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testKeepsTheHistoryAcrossARestart() {
        var history = History()
        history.ask("what changed", at: Date(timeIntervalSince1970: 1_000))
        history.reply("Two files.")
        history.end(at: Date(timeIntervalSince1970: 1_002))
        HistoryFile(folder: folder).save(history)
        XCTAssertEqual(HistoryFile(folder: folder).load(), history)
    }

    func testStartsEmptyWhenNothingWasKeptOrItNoLongerReads() throws {
        XCTAssertEqual(HistoryFile(folder: folder).load(), History())
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appendingPathComponent("history.json"))
        XCTAssertEqual(HistoryFile(folder: folder).load(), History())
    }
}
