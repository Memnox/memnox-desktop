import XCTest

@testable import MemnoxVoiceCore

final class ProjectToolCatalogTests: XCTestCase {
    private let notes = MemorySourceView(id: "s1", kind: .obsidian, name: "Launch notes", location: "/notes", project: "prj_1")

    func testHoldsACardForEveryToolOneMacLinksWithCodeLast() {
        let cards = ProjectToolCatalog.cards(sampleProject, sources: [notes])
        XCTAssertFalse(ProjectToolCatalog.showsTeamTools)
        XCTAssertEqual(cards.map(\.slot.title), ["Files", "Docs", "Apps", "Repositories"])
        XCTAssertEqual(cards.first?.linked.map(\.name), ["Launch notes"])
        XCTAssertEqual(cards.first { $0.slot == .apps }?.linked.map(\.name), ["github"])
        XCTAssertEqual(cards.last?.linked.map(\.kind), [.folder])
    }

    func testNarrowsByCategoryAndBySearchOverWhatIsLinked() {
        let cards = ProjectToolCatalog.cards(sampleProject, sources: [notes])
        XCTAssertEqual(ProjectToolCatalog.shown(cards, category: .building, query: "").map(\.slot), [.apps, .repositories])
        XCTAssertEqual(ProjectToolCatalog.shown(cards, category: nil, query: "launch").map(\.slot), [.files])
        XCTAssertEqual(ProjectToolCatalog.categories(cards).map(\.count), [2, 2])
        XCTAssertEqual(ProjectToolCatalog.categories(cards).map(\.title), ["Files and docs", "Code and apps"])
    }

    func testSaysWhatIsLinkedAndHowOneIsAdded() {
        let cards = ProjectToolCatalog.cards(sampleProject, sources: [notes])
        XCTAssertEqual(ProjectToolCatalog.linkedLine(cards[0]), "Launch notes linked")
        XCTAssertEqual(ProjectToolCatalog.linkedLine(cards[1]), "Nothing linked yet")
        XCTAssertEqual(ProjectToolSlot.apps.adding(joined: false), .apps)
        XCTAssertEqual(ProjectToolSlot.files.adding(joined: false), .files)
        XCTAssertNil(ProjectToolSlot.repositories.adding(joined: false))
        XCTAssertEqual(ProjectToolSlot.repositories.adding(joined: true), .cloud)
        XCTAssertEqual(ProjectToolSlot.channels.adding(joined: true), .cloud)
        XCTAssertEqual(ProjectToolSlot.allCases.filter(\.isTeamTool), [.channels, .meetings, .tickets])
    }
}
