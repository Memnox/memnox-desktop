import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// What the app takes out of each agent's own files when no memnox is left to ask: only what names Memnox, so every
/// hook and server the person wrote stays as it was.
final class RuntimeLeftoversTests: XCTestCase {
    private let ours = #"{"type":"command","command":"/Users/bo/.memnox/bin/memnox-edit-hook --agent claude-code"}"#
    private let theirs = #"{"type":"command","command":"say done"}"#

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func object(_ data: Data?) throws -> NSDictionary {
        let data = try XCTUnwrap(data)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    func testTakesOurNestedHookOutAndKeepsTheirsBesideIt() throws {
        let settings = json(#"{"model":"opus","hooks":{"PreToolUse":[{"matcher":"*","hooks":[\#(ours),\#(theirs)]}]}}"#)
        let kept = try object(RuntimeLeftovers.withoutHooks(settings))
        let expected = try object(json(#"{"model":"opus","hooks":{"PreToolUse":[{"matcher":"*","hooks":[\#(theirs)]}]}}"#))
        XCTAssertEqual(kept, expected)
    }

    func testTakesAFlatHookOutAndTheHooksKeyWithItWhenNothingIsLeft() throws {
        let cursor = json(#"{"version":1,"hooks":{"beforeShellExecution":[\#(ours)]}}"#)
        let kept = try object(RuntimeLeftovers.withoutHooks(cursor))
        XCTAssertEqual(kept, try object(json(#"{"version":1}"#)))
    }

    func testLeavesAFileWithNothingOfOursOrNotPlainJsonAlone() {
        XCTAssertNil(RuntimeLeftovers.withoutHooks(json(#"{"hooks":{"Stop":[{"hooks":[\#(theirs)]}]}}"#)))
        XCTAssertNil(RuntimeLeftovers.withoutHooks(json("{ // a comment\n}")))
        XCTAssertNil(RuntimeLeftovers.withoutHooks(json(#"{"model":"opus"}"#)))
    }

    func testTakesOurServersOutAndKeepsOneThePersonNamedMemnoxForSomethingElse() throws {
        let config = json(#"""
        {"mcpServers":{"memnox-session":{"command":"memnox-session","args":["--agent","cursor"]},
         "memnox":{"type":"http","url":"https://api.memnox.com/mcp"},"github":{"command":"gh-mcp"}}}
        """#)
        let kept = try object(RuntimeLeftovers.withoutServers(config))
        XCTAssertEqual(kept, try object(json(#"{"mcpServers":{"github":{"command":"gh-mcp"}}}"#)))
        XCTAssertNil(RuntimeLeftovers.withoutServers(json(#"{"mcpServers":{"memnox":{"command":"my-notes"}}}"#)))
    }

    func testCutsOurCodexTablesAndTheirSubTablesAndNothingElse() throws {
        let toml = """
        model = "o5"

        [mcp_servers.memnox]
        url = "https://api.memnox.com/mcp"

        [mcp_servers.memnox.http_headers]
        Authorization = "Bearer x"

        [mcp_servers.linear]
        command = "linear-mcp"

        [mcp_servers.memnox-session]
        command = "memnox-session"
        args = ["--agent", "codex"]
        """
        let kept = try XCTUnwrap(RuntimeLeftovers.withoutTomlServers(toml))
        XCTAssertEqual(kept, """
        model = "o5"

        [mcp_servers.linear]
        command = "linear-mcp"
        """)
        XCTAssertNil(RuntimeLeftovers.withoutTomlServers("[mcp_servers.memnox]\ncommand = \"my-notes\"\n"))
    }

    func testOnlyTheBinsLeadingIntoThePackageAreTaken() {
        let links = [(name: "memnox", resolved: "/Users/bo/memnox-runtime/packages/cli/dist/index.js"),
                     (name: "memnox-session", resolved: "/Users/bo/memnox-runtime/packages/cli/dist/bin/session.js"),
                     (name: "memnox-other", resolved: "/Users/bo/memnox-runtime/packages/cli-other/x.js"),
                     (name: "tsc", resolved: "/opt/homebrew/lib/node_modules/typescript/bin/tsc")]
        XCTAssertEqual(RuntimeLeftovers.binsInto("/Users/bo/memnox-runtime/packages/cli", among: links),
                       ["memnox", "memnox-session"])
    }

    func testTakesTheRuntimePathBlockOutAndLeavesTheAppsAndThePersonsLines() throws {
        let profile = """
        export EDITOR=vim

        # >>> memnox >>>
        export PATH="$HOME/.memnox/bin:$PATH"
        # <<< memnox <<<
        alias g=git
        """
        let kept = try XCTUnwrap(ProfileBlock.without(profile, between: RuntimeLeftovers.pathBegin, and: RuntimeLeftovers.pathEnd))
        XCTAssertEqual(kept, "export EDITOR=vim\nalias g=git")
        XCTAssertNil(ProfileBlock.without("# >>> memnox app >>>\nx\n# <<< memnox app <<<\n",
                                          between: RuntimeLeftovers.pathBegin, and: RuntimeLeftovers.pathEnd))
    }
}
