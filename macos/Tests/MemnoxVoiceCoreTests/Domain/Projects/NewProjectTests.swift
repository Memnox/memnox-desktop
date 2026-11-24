import XCTest
@testable import MemnoxVoiceCore

final class NewProjectTests: XCTestCase {
    func testASkippedNameIsTheFoldersOwn() {
        XCTAssertEqual(NewProject.name(typed: "  ", folder: "/work/acme-site"), "acme-site")
        XCTAssertEqual(NewProject.name(typed: " Website ", folder: "/work/acme-site"), "Website")
    }

    func testWhatAgentsShouldKnowIsOneThingPerLine() {
        XCTAssertEqual(NewProject.instructions("Refunds over 500 go to finance.\n\n  No email on Sunday. \n"),
                       ["Refunds over 500 go to finance.", "No email on Sunday."])
        XCTAssertEqual(NewProject.instructions("   \n"), [])
    }

    func testSaysHowManyThingsAgentsWillKnow() {
        XCTAssertEqual(NewProject.remembered(1), "Agents here will know that from now on.")
        XCTAssertEqual(NewProject.remembered(3), "Agents here will know those 3 things from now on.")
    }

    func testRenamesOnlyWhenTheAnswerDiffers() {
        XCTAssertNil(NewProject.draft(of: sampleProject, name: sampleProject.name))
        XCTAssertEqual(NewProject.draft(of: sampleProject, name: "Website")?.name, "Website")
    }
}
