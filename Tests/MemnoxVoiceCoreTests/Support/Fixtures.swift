import Foundation
import XCTest

@testable import MemnoxVoiceCore

func line(_ json: String) throws -> DaemonResponse { try decodeLine(json) }

func event(_ json: String) throws -> DaemonEvent {
    try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":"# + json + "}").event)
}
