import XCTest
@testable import MemnoxVoiceCore

final class ActivityWordsTests: XCTestCase {
    private let home = "/Users/someone/Documents/Memnox-saas/memnox-client"

    func testNamesTheFileAndTheProjectItSitsIn() {
        XCTAssertEqual(ActivityWords.line(operation: "file.edit", target: "\(home)/apps/app/components/page/form-parts.tsx"),
                       "Changed form-parts.tsx in memnox-client")
    }

    func testSaysFilesInAProjectWhenTheTargetIsAFolder() {
        XCTAssertEqual(ActivityWords.line(operation: "filesystem.write", target: "\(home)/apps/app/."), "Changed files in memnox-client")
    }

    func testFallsBackToTheFolderAFileSitsInWhenNothingMarksAProject() {
        XCTAssertEqual(ActivityWords.line(operation: "filesystem.read", target: "/etc/hosts"), "Read hosts in etc")
    }

    func testSaysCommandsGitAndWebInPlainWords() {
        XCTAssertEqual(ActivityWords.line(operation: "shell.exec", target: "npm run build"), "Ran npm")
        XCTAssertEqual(ActivityWords.line(operation: "git.push", target: "origin main"), "Pushed")
        XCTAssertEqual(ActivityWords.line(operation: "http.request", target: "https://api.github.com/repos"), "Reached api.github.com")
    }

    func testKeepsAnActionItDoesNotKnowAsWritten() {
        XCTAssertEqual(ActivityWords.line(operation: "cli.ask", target: "me"), "cli.ask me")
        XCTAssertEqual(ActivityWords.line(operation: "vault.unseal", target: nil), "vault.unseal")
    }
}
