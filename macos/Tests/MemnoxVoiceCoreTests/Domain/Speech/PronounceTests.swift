import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The words of an agent's world, said the way a person says them.
final class PronounceTests: XCTestCase {
    func testReadsTheWordsOfAnAgentsWorldTheWayAPersonSaysThem() {
        XCTAssertEqual(pronounced("Run npm publish from the CLI."), "Run N P M publish from the C L I.")
        XCTAssertEqual(pronounced("It changed Speech.swift and packages/cli/src/show-tool.ts."), "It changed Speech dot swift and show tool dot T S.")
        XCTAssertEqual(pronounced("Turn it on with memnox protect --enforce."), "Turn it on with memnox protect dash dash enforce.")
        XCTAssertEqual(pronounced("Claude Code in memnox-runtime opened two PRs."), "Claude Code in memnox runtime opened two P R's.")
        XCTAssertEqual(pronounced("The UI in VS Code reads the MCP config."), "The U I in V S Code reads the M C P config.")
        XCTAssertEqual(pronounced("OK, I'll check the JSON."), "okay, I'll check the Jason.")
        XCTAssertEqual(pronounced("A rule in memnox.policies.toml."), "A rule in memnox dot policies dot tommel.")
        XCTAssertEqual(pronounced("It spent 3.5 minutes on it."), "It spent 3.5 minutes on it.")
        XCTAssertEqual(pronounced("Five agents: Codex CLI and Cursor."), "Five agents: Codex and Cursor.")
        XCTAssertEqual(pronounced("It is on feat/voice-answers."), "It is on feature voice answers.")
        XCTAssertEqual(pronounced("It made e0634ce4 on main."), "It made commit on main.")
        XCTAssertEqual(pronounced("Memnox 0.13.8 shipped."), "Memnox 0 point 13 point 8 shipped.")
        XCTAssertEqual(pronounced("The brain took 640ms in iTerm."), "The brain took 640 milliseconds in eye term.")
        XCTAssertEqual(pronounced("It reviewed PR #88 at https://github.com/memnox/runtime/pull/88."), "It reviewed P R number 88 at github dot com.")
        XCTAssertEqual(pronounced("Run pnpm test in zsh."), "Run P N P M test in Z shell.")
    }

    func testReadsAnEmailAddressWholeWithItsEnding() {
        XCTAssertEqual(pronounced("Your Gmail is connected, as moiserushanika2006@gmail.com."), "Your Gmail is connected, as moiserushanika2006 at gmail dot com.")
        XCTAssertEqual(pronounced("It goes to moise.r@memnox.com, asking him."), "It goes to moise dot r at memnox dot com, asking him.")
    }
}
