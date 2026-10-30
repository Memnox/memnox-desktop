import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the remote server's headers in shared/tauri-core/test/mcp-hub.test.ts, so the Mac writes them as Windows and Linux do.
final class HeaderLinesTests: XCTestCase {
    func testKeepsACredentialHeaderAsASecretFromItsName() {
        XCTAssertTrue(HeaderLines.isCredential("Authorization"))
        XCTAssertTrue(HeaderLines.isCredential("x-api-key"))
        XCTAssertTrue(HeaderLines.isCredential("Cookie"))
        XCTAssertFalse(HeaderLines.isCredential("X-Trace"))
    }

    func testRefusesWhatTheRuntimeWouldRefuse() {
        XCTAssertEqual(HeaderLines.problem([HeaderRow(name: "Authorization", value: "Bearer abc")]),
                       "Authorization carries a credential, so keep its value as a secret.")
        XCTAssertEqual(HeaderLines.problem([HeaderRow(name: "Bad Name", value: "x")]), "Bad Name is not a header name.")
        XCTAssertEqual(HeaderLines.problem([HeaderRow(name: "X-Team", value: "a"), HeaderRow(name: "x-team", value: "b")]), "x-team is given twice.")
        XCTAssertEqual(HeaderLines.problem([HeaderRow(name: "X-Team", value: " ")]), "Give the value X-Team is sent with.")
        XCTAssertNil(HeaderLines.problem([HeaderRow(), HeaderRow(name: "Authorization", value: "Bearer abc", secret: true)]))
    }

    func testSendsAKeptHeaderAsItsReferenceWithTheSchemeInFront() {
        XCTAssertEqual(HeaderLines.secretName(server: "docs", header: "X-Api-Key"), "docs-x-api-key")
        let bearer = HeaderLines.reference("Bearer abc.def", secretName: "docs-authorization")
        XCTAssertEqual(bearer.sent, "Bearer memnox-secret:docs-authorization")
        XCTAssertEqual(bearer.secret, "abc.def")
        let plain = HeaderLines.reference("abc", secretName: "docs-x-api-key")
        XCTAssertEqual(plain.sent, "memnox-secret:docs-x-api-key")
        XCTAssertEqual(plain.secret, "abc")
        let written = HeaderLines.headers(server: "docs", rows: [HeaderRow(name: "Authorization", value: "Bearer abc", secret: true),
                                                                 HeaderRow(name: "X-Team", value: "core")])
        XCTAssertEqual(written.headers, ["Authorization": "Bearer memnox-secret:docs-authorization", "X-Team": "core"])
        XCTAssertEqual(written.secrets, ["docs-authorization": "abc"])
    }

    func testTakesPlainHttpOnlyForThisMac() {
        XCTAssertNil(HeaderLines.addressProblem("https://mcp.example.com/mcp"))
        XCTAssertNil(HeaderLines.addressProblem("http://localhost:3000/mcp"))
        XCTAssertNil(HeaderLines.addressProblem("http://127.0.0.1:3000/mcp"))
        XCTAssertNil(HeaderLines.addressProblem("http://[::1]:3000/mcp"))
        XCTAssertEqual(HeaderLines.addressProblem("http://mcp.example.com/mcp"),
                       "Plain http is only for a server on this Mac, at localhost or 127.0.0.1. Use https for one anywhere else.")
        XCTAssertEqual(HeaderLines.addressProblem("ftp://example.com"), "A remote server is reached over http or https.")
        XCTAssertEqual(HeaderLines.addressProblem("mcp.example"), "mcp.example is not an address.")
    }

    func testListsHeadersByNameWithWhetherTheirSecretIsHeld() throws {
        let json = #"{"name":"docs","transport":"http","url":"https://mcp.example.com","envNames":[],"headerNames":["Authorization","X-Team"],"governed":true,"toolCount":0,"health":{"state":"unknown"},"agents":[],"secretsHeld":{"docs-authorization":false},"callsThisWeek":0}"#
        let server = try JSONDecoder().decode(McpHubServerView.self, from: Data(json.utf8))
        let lines = HeaderLines.lines(server)
        XCTAssertEqual(lines.map(\.name), ["Authorization", "X-Team"])
        XCTAssertEqual(lines.map(\.held), [false, nil])
    }
}
