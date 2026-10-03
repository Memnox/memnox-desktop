import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Bytes from the socket cut into whole protocol lines.
final class LineSplitterTests: XCTestCase {
    func testSplitsLinesAcrossReads() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.push(Data("{\"a\":1}\n{\"b\"".utf8)), ["{\"a\":1}"])
        XCTAssertEqual(splitter.push(Data(":2}\n\n".utf8)), ["{\"b\":2}"])
    }
}
