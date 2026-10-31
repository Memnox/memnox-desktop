import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Looking words first, every display only to point, and a ring drawn where the brain found something.
final class PointingTests: XCTestCase {
    private final class Eyes: Presenter {
        var looks: [LookPicture?] = []
        var points: [(ScreenSpot, String)] = []
        var lands = true
        func open(_ host: DisplayHost?) async -> Bool { true }
        func live(session: String, host: DisplayHost?) async {}
        func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
        func card(_ card: SummaryCard) async {}
        func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { .landed }
        func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { .landed }
        func launch(_ command: String, in folder: String?) async -> Typed { .landed }
        func walk(_ walk: WalkCard) async {}
        func scan(_ agents: [AgentNode], title: String) async {}
        func trace(_ trace: TraceData, title: String) async {}
        func board(title: String) async {}
        func look(app: String?, picture: LookPicture?) async -> Sight? {
            looks.append(picture)
            return Sight(app: "Finder", text: "Documents")
        }
        func readTab(of host: DisplayHost) async -> Sight? { Sight(app: "Terminal", text: "tab words") }
        func point(at spot: ScreenSpot, label: String) async -> Bool {
            points.append((spot, label))
            return lands
        }
    }

    var link: ScriptedLink!
    private var eyes: Eyes!
    var conversation: Conversation!

    override func setUp() {
        link = ScriptedLink()
        eyes = Eyes()
        conversation = Conversation(link: link, speaker: RecordingSpeaker(), key: PersonKey(), face: RecordingFace(),
                                    owner: MemoryOwner(nil), presenter: eyes)
    }

    func testLooksWordsFirstAndTakesThePictureTheRuntimeAskedFor() async throws {
        await conversation.handle(try event(#"{"kind":"show","subject":"dsp_1","agent":"memnox","summary":"","at":"2026-10-26T00:00:00Z","display":"look","title":""}"#))
        await conversation.handle(try event(#"{"kind":"show","subject":"dsp_2","agent":"memnox","summary":"","at":"2026-10-26T00:00:00Z","display":"look","title":"","via":"picture"}"#))
        await conversation.handle(try event(#"{"kind":"show","subject":"dsp_3","agent":"memnox","summary":"","at":"2026-10-26T00:00:00Z","display":"look","title":"","via":"screens","host":{"tty":"ttys001"}}"#))
        XCTAssertEqual(eyes.looks, [nil, .window, .screens])
        XCTAssertEqual(link.sent.last?.sight?.app, "Finder")
    }

    func testDrawsTheRingWhereTheBrainPointedAndSaysItWasShown() async throws {
        let shown = try event(#"{"kind":"show","subject":"dsp_4","agent":"memnox","summary":"Save button","at":"2026-10-26T00:00:00Z","display":"point","title":"Save button","sessionId":"screen","point":{"screen":1,"x":640,"y":300,"width":1280,"height":720}}"#)
        XCTAssertEqual(shown.displayKind, .point)
        await conversation.handle(shown)
        XCTAssertEqual(eyes.points.first?.0, ScreenSpot(screen: 1, x: 640, y: 300, width: 1280, height: 720))
        XCTAssertEqual(eyes.points.first?.1, "Save button")
        XCTAssertEqual(link.sent.last?.method, "delivered")
        XCTAssertEqual(link.sent.last?.answer, "typed")
    }

    func testSaysItFailedWhenTheSpotIsOnNoDisplay() async throws {
        eyes.lands = false
        await conversation.handle(try event(#"{"kind":"show","subject":"dsp_5","agent":"memnox","summary":"x","at":"2026-10-26T00:00:00Z","display":"point","title":"x","point":{"screen":3,"x":1,"y":1,"width":1280,"height":720}}"#))
        XCTAssertEqual(link.sent.last?.answer, "failed")
        await conversation.handle(try event(#"{"kind":"show","subject":"dsp_6","agent":"memnox","summary":"x","at":"2026-10-26T00:00:00Z","display":"point","title":"x"}"#))
        XCTAssertEqual(eyes.points.count, 1)
    }

    func testScalesPicturePixelsToTheDisplaysPoints() {
        let spot = ScreenSpot(screen: 0, x: 640, y: 400, width: 1280, height: 800)
        let points = spot.points(across: 1440, down: 900)
        XCTAssertEqual(points?.x, 720)
        XCTAssertEqual(points?.y, 450)
        XCTAssertNil(ScreenSpot(screen: 0, x: 1300, y: 10, width: 1280, height: 800).points(across: 1440, down: 900))
        XCTAssertNil(ScreenSpot(screen: 0, x: 0, y: 0, width: 0, height: 0).points(across: 1440, down: 900))
    }

    func testSendsEveryScreenPictureWithItsPixelSize() throws {
        var request = DaemonRequest(id: 1, method: .seen)
        request.sight = Sight(app: "Finder", screens: [ScreenPicture(image: "/s/0.jpg", width: 1280, height: 800)])
        let text = String(data: try encodeLine(request), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains(#""screens":[{"height":800,"image":"\/s\/0.jpg","width":1280}]"#), text)
    }
}
