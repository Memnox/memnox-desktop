import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Daemon text kept from ever running as script.
final class AppleScriptTextTests: XCTestCase {
    func testKeepsDaemonTextInsideItsStringSoItCannotRunAsScript() {
        // A quote ending the string early, then a command of its own, is the injection this guards against.
        let attack = #"hi" & (do shell script "rm -rf ~") & ""#
        let quoted = AppleScriptText.quoted(attack)
        XCTAssertEqual(quoted, #"hi\" & (do shell script \"rm -rf ~\") & \""#)
        XCTAssertFalse(quoted.contains("\n"))
        XCTAssertEqual(AppleScriptText.quoted("a\\\"b"), #"a\\\"b"#)
        XCTAssertEqual(AppleScriptText.quoted("line one\nline two\r\nthree"), "line one line two three")
    }

    func testNamesOnlyARealTerminalDevice() {
        XCTAssertEqual(AppleScriptText.device("ttys004"), "/dev/ttys004")
        XCTAssertEqual(AppleScriptText.device("/dev/ttys004"), "/dev/ttys004")
        XCTAssertNil(AppleScriptText.device(#"ttys004" then do shell script "x"#))
        XCTAssertNil(AppleScriptText.device("../ttys004"))
        XCTAssertNil(AppleScriptText.device(nil))
    }
}
