import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A turn end to end: what is heard, what is sent, and what is said back.
final class TalkingTests: XCTestCase {
    func answer() throws -> [DaemonResponse] {
        [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Two are working. "}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
        ]
    }

    func testSaysNothingBeforeAnAnswerThatLooksNothingUpHoweverSlow() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0.3, answer: try answer()),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["One sec."]
        )
        await conversation.heard("oh that's cool")
        XCTAssertEqual(speaker.said, ["Two are working."])
    }

    func testSaysNothingAndWaitsForTheRestWhenTheyStoppedMidThought() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__keep_listening"}}"#),
                // The brain writing on after keep_listening anyway, which must not be said over them.
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"I'm listening for what you want to say about it."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["One sec."]
        )
        await conversation.heard("OK so I was working on the feature")
        XCTAssertEqual(speaker.said, [])
        XCTAssertTrue(conversation.takeHold())
        XCTAssertFalse(conversation.takeHold())
        XCTAssertFalse(conversation.takeEnd())
    }

    func testAnswersItsNameAloneWithoutAskingTheBrain() async throws {
        let speaker = RecordingSpeaker()
        let link = SlowLink(seconds: 0, answer: try answer())
        let conversation = Conversation(
            link: link, speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        await conversation.heard("Ma'am Knox")
        XCTAssertEqual(speaker.said.count, 1)
        // The first call in a while is greeted for the hour, and the brain's answer is never said.
        XCTAssertTrue(speaker.said[0].hasPrefix("Good "))
    }

    func testSaysTheWordsBeforeAToolCallAsTheirOwnSentence() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"You mean Codex?"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__sessions"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Codex has nothing running."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        await conversation.heard("what is coco doing")
        XCTAssertEqual(speaker.said, ["You mean Codex?", "Codex has nothing running."])
    }

    func testSaysNoLetMeLookBeforeSomethingItDoes() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__watch_for"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"I'll tell you when it finishes."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["Let me look."]
        )
        await conversation.heard("yes please tell me")
        XCTAssertEqual(speaker.said, ["I'll tell you when it finishes."])
    }

    func testSaysLetMeLookTheMomentItStartsLookingSomethingUp() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__changes"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Two files changed."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["Let me look."]
        )
        await conversation.heard("what did it change")
        XCTAssertEqual(speaker.said, ["Let me look.", "Two files changed."])
    }

    func testPutsACardUpAndOpensAWindowWhenAsked() async throws {
        final class RecordingPresenter: Presenter {
            var cards: [String] = []
            var shown: [SummaryCard] = []
            var opened: [DisplayHost?] = []
            var live: [String] = []
            func live(session: String, host: DisplayHost?) async { live.append(session) }
            func focus(session: String, host: DisplayHost?) async -> Typed { live.append("focus \(session)"); return .landed }
            func open(_ host: DisplayHost?) async -> Bool {
                opened.append(host)
                return host != nil
            }
            func card(_ card: SummaryCard) async {
                cards.append("\(card.title): \(card.text)")
                shown.append(card)
            }
            var typed: [String] = []
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed {
                typed.append(text)
                return host?.tty != nil ? .landed : Typed(.failed)
            }
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed {
                typed.append("\(session): \(text)")
                return .landed
            }
            var walks: [WalkCard] = []
            func launch(_ command: String, in folder: String?) async -> Typed {
                typed.append("launch \(folder ?? ""): \(command)")
                return .landed
            }
            func walk(_ walk: WalkCard) async { walks.append(walk) }
            func scan(_ agents: [AgentNode], title: String) async {}
            func trace(_ trace: TraceData, title: String) async {}
            var boards: [String] = []
            func board(title: String) async { boards.append(title) }
        }
        let presenter = RecordingPresenter()
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: []), speaker: speaker, key: PersonKey(),
            face: RecordingFace(), owner: MemoryOwner(nil), presenter: presenter
        )
        let card = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_1","agent":"claude-code","summary":"It added **two** tests.","at":"2026-10-01T00:00:00Z","display":"card","title":"Checkout","files":[{"path":"src/cart.ts","added":3,"removed":1},{"path":"logo.png"}],"excerpt":{"path":"src/cart.ts","lines":["-const a = 1;","+const a = 2;"]}}}"#)
        let open = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_2","agent":"claude-code","summary":"Checkout","at":"2026-10-01T00:00:00Z","display":"open","host":{"app":"iTerm","tty":"ttys004"}}}"#)
        let lost = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_3","agent":"claude-code","summary":"Checkout","at":"2026-10-01T00:00:00Z","display":"open"}}"#)
        for response in [card, open, lost] { await conversation.handle(try XCTUnwrap(response.event)) }
        XCTAssertEqual(presenter.cards, ["Checkout: It added **two** tests."])
        let type = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_4","agent":"claude-code","summary":"push the voice branch","at":"2026-10-01T00:00:00Z","display":"type","host":{"app":"iTerm","tty":"ttys004"}}}"#)
        let prefill = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_5","agent":"claude-code","summary":"add a test","at":"2026-10-01T00:00:00Z","display":"prefill","sessionId":"cb694eae-78b4-439d-adce-edb96cac223e","host":{"app":"Visual Studio Code"}}}"#)
        for response in [type, prefill] { await conversation.handle(try XCTUnwrap(response.event)) }
        XCTAssertEqual(presenter.typed, ["push the voice branch", "cb694eae-78b4-439d-adce-edb96cac223e: add a test"])
        XCTAssertEqual(presenter.shown.first?.files, [CardFile(path: "src/cart.ts", added: 3, removed: 1), CardFile(path: "logo.png")])
        XCTAssertEqual(presenter.shown.first?.excerpt, CardExcerpt(path: "src/cart.ts", lines: ["-const a = 1;", "+const a = 2;"]))
        XCTAssertEqual(presenter.opened.first??.tty, "ttys004")
        XCTAssertEqual(speaker.said, ["My apologies, I could not bring its window forward."])
        let live = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_6","agent":"claude-code","summary":"Checkout","at":"2026-10-01T00:00:00Z","display":"open","sessionId":"ses_live","host":{"app":"Visual Studio Code"}}}"#)
        await conversation.handle(try XCTUnwrap(live.event))
        // A session it knows opens live on screen, rather than jumping straight to another app.
        XCTAssertEqual(presenter.live, ["ses_live"])
        let all = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_7","agent":"memnox","summary":"","at":"2026-10-01T00:00:00Z","display":"sessions","title":"Your sessions"}}"#)
        await conversation.handle(try XCTUnwrap(all.event))
        XCTAssertEqual(presenter.boards, ["Your sessions"])
    }

    func testStartsASessionAndPutsAWalkThroughUp() async throws {
        final class Recording: Presenter {
            var launched: [String] = []
            var walks: [WalkCard] = []
            func live(session: String, host: DisplayHost?) async {}
            func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
            func open(_ host: DisplayHost?) async -> Bool { true }
            func card(_ card: SummaryCard) async {}
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { .landed }
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { .landed }
            func launch(_ command: String, in folder: String?) async -> Typed {
                launched.append("\(folder ?? "nowhere"): \(command)")
                return .landed
            }
            func walk(_ walk: WalkCard) async { walks.append(walk) }
            var scanned: [String] = []
            func scan(_ agents: [AgentNode], title: String) async { scanned = agents.map(\.kind) + [title] }
            func trace(_ trace: TraceData, title: String) async {}
            func board(title: String) async {}
        }
        let presenter = Recording()
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [try line(#"{"id":1,"ok":true,"outcome":"kept"}"#)]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil), presenter: presenter
        )
        let launch = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_7","agent":"claude-code","summary":"memnox run -- claude 'fix it'","at":"2026-10-01T00:00:00Z","display":"launch","host":{"cwd":"/r/memnox-cloud"}}}"#)
        let walk = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_8","agent":"claude-code","summary":"Walk","at":"2026-10-01T00:00:00Z","display":"walk","title":"Card fix","sessionId":"ses_1","pages":[{"path":"src/card.ts","note":"It **stays** flat.","added":2,"lines":["+flat"]}]}}"#)
        for response in [launch, walk] { await conversation.handle(try XCTUnwrap(response.event)) }
        XCTAssertEqual(presenter.launched, ["/r/memnox-cloud: memnox run -- claude 'fix it'"])
        XCTAssertEqual(presenter.walks.first?.title, "Card fix")
        XCTAssertEqual(presenter.walks.first?.pages, [WalkPage(path: "src/card.ts", note: "It stays flat.", added: 2, lines: ["+flat"])])
        XCTAssertEqual(speaker.said, [])
        let scan = try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_9","agent":"memnox","summary":"Your agents","at":"2026-10-01T00:00:00Z","display":"agents","title":"Your agents","agents":[{"id":"agt_claude-code","kind":"claude-code","name":"Claude Code","servers":3,"reaches":["shell"],"working":1,"open":0}]}}"#)
        await conversation.handle(try XCTUnwrap(scan.event))
        XCTAssertEqual(presenter.scanned, ["claude-code", "Your agents"])
    }

    func testTellsTheBrainWhenTypingFailedAndOnlySpeaksForAnOlderDaemon() async throws {
        final class FailingPresenter: Presenter {
            func live(session: String, host: DisplayHost?) async {}
            func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
            func open(_ host: DisplayHost?) async -> Bool { false }
            func card(_ card: SummaryCard) async {}
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { Typed(.failed, "no tab") }
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { Typed(.failed) }
            func launch(_ command: String, in folder: String?) async -> Typed { Typed(.failed) }
            func walk(_ walk: WalkCard) async {}
            func scan(_ agents: [AgentNode], title: String) async {}
            func trace(_ trace: TraceData, title: String) async {}
            func board(title: String) async {}
        }
        let type = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_4","agent":"claude-code","summary":"commit it","at":"2026-10-01T00:00:00Z","display":"type","host":{"app":"iTerm","tty":"ttys004"}}}"#).event)
        let heard = RecordingSpeaker()
        let listening = Conversation(
            link: SlowLink(seconds: 0, answer: [try line(#"{"id":1,"ok":true,"outcome":"kept"}"#)]),
            speaker: heard, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil), presenter: FailingPresenter()
        )
        await listening.handle(type)
        // The brain waiting on send_instruction says it, so the app says nothing over it.
        XCTAssertEqual(heard.said, [])
        let older = RecordingSpeaker()
        let unheard = Conversation(
            link: SlowLink(seconds: 0, answer: []),
            speaker: older, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil), presenter: FailingPresenter()
        )
        await unheard.handle(type)
        XCTAssertEqual(older.said, ["My apologies, I could not type it into its terminal."])
    }

    func testSaysHowToLetItTypeOnceAndThenOnlyWhereTheWordsAre() async throws {
        final class LockedPresenter: Presenter {
            func live(session: String, host: DisplayHost?) async {}
            func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
            func open(_ host: DisplayHost?) async -> Bool { false }
            func card(_ card: SummaryCard) async {}
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { Typed(.failed) }
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed {
                Typed(.notAllowed, "Memnox is not allowed to type yet")
            }
            func launch(_ command: String, in folder: String?) async -> Typed { Typed(.failed) }
            func walk(_ walk: WalkCard) async {}
            func scan(_ agents: [AgentNode], title: String) async {}
            func trace(_ trace: TraceData, title: String) async {}
            func board(title: String) async {}
        }
        let prefill = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_5","agent":"claude-code","summary":"check the git history","at":"2026-10-01T00:00:00Z","display":"prefill","sessionId":"ses_1","host":{"app":"Visual Studio Code"}}}"#).event)
        // macOS 27 renamed the pane, so each release hears the name its own System Settings shows.
        for (version, pane) in [(26, "Accessibility"), (27, "Device Control and Data Access")] {
            let speaker = RecordingSpeaker()
            let conversation = Conversation(
                link: SlowLink(seconds: 0, answer: [try line(#"{"id":1,"ok":true,"outcome":"kept"}"#)]),
                speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil), presenter: LockedPresenter(),
                macOSMajorVersion: version
            )
            await conversation.handle(prefill)
            await conversation.handle(prefill)
            XCTAssertEqual(speaker.said.count, 2)
            XCTAssertTrue(speaker.said[0].contains(pane), "macOS \(version)")
            XCTAssertEqual(speaker.said[1], "Your words are on the clipboard again.")
        }
    }

    func testSpeaksUpWithTheBriefAndFallsBackToTheFact() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#)]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        let notice = try line(#"{"id":0,"ok":true,"event":{"kind":"notice","subject":"ntc_1","agent":"claude-code","summary":"Claude Code just made a commit.","at":"2026-10-01T00:00:00Z","notice":"committed"}}"#)
        await conversation.handle(try XCTUnwrap(notice.event))
        XCTAssertEqual(speaker.said, ["Claude Code just made a commit."])
    }

    func testEndsTheConversationWhenTheBrainSaysThePersonIsDone() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__end_conversation"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Right, got it."}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["One sec."]
        )
        await conversation.heard("no it's fine")
        XCTAssertEqual(speaker.said, ["Right, got it."])
        XCTAssertTrue(conversation.takeEnd())
        XCTAssertFalse(conversation.takeEnd())
    }

    func testSendsNothingWhenTheRecognizerHeardOnlyPunctuation() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: try answer()),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        await conversation.heard(" . ")
        XCTAssertEqual(speaker.said, [])
    }

    func testNeverSaysLetMeLookTwoTurnsRunning() async throws {
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: [
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"tool","tool":"mcp__memnox-operator__sessions"}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Two are working. "}}"#),
                try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
            ]),
            speaker: speaker, key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil),
            fillers: ["One sec."]
        )
        await conversation.heard("what are they doing")
        await conversation.heard("and now")
        XCTAssertEqual(speaker.said.filter { $0 == "One sec." }.count, 1)
    }

    func testTypesOneMessageAtATimeSoTwoNeverMixTheirLetters() async throws {
        // Records when each message starts and ends, slowly enough that two at once would overlap.
        final class SlowTyping: Presenter, @unchecked Sendable {
            private let lock = NSLock()
            private var marks: [String] = []
            var log: [String] { lock.lock(); defer { lock.unlock() }; return marks }
            private func mark(_ text: String) { lock.lock(); marks.append(text); lock.unlock() }
            func live(session: String, host: DisplayHost?) async {}
            func open(_ host: DisplayHost?) async -> Bool { true }
            func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
            func card(_ card: SummaryCard) async {}
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { .landed }
            func launch(_ command: String, in folder: String?) async -> Typed { .landed }
            func walk(_ walk: WalkCard) async {}
            func scan(_ agents: [AgentNode], title: String) async {}
            func trace(_ trace: TraceData, title: String) async {}
            func board(title: String) async {}
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed {
                mark("start \(text)")
                try? await Task.sleep(nanoseconds: 50_000_000)
                mark("end \(text)")
                return .landed
            }
        }
        let presenter = SlowTyping()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: []), speaker: RecordingSpeaker(), key: PersonKey(),
            face: RecordingFace(), owner: MemoryOwner(nil), presenter: presenter
        )
        let first = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_1","agent":"claude-code","summary":"add the cancel button","at":"2026-10-01T00:00:00Z","display":"type","host":{"app":"iTerm","tty":"ttys004"}}}"#).event)
        let second = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_2","agent":"claude-code","summary":"and a test for it","at":"2026-10-01T00:00:00Z","display":"type","host":{"app":"iTerm","tty":"ttys004"}}}"#).event)
        async let one: Void = conversation.handle(first)
        try? await Task.sleep(nanoseconds: 5_000_000)
        async let two: Void = conversation.handle(second)
        _ = await (one, two)
        XCTAssertEqual(presenter.log, ["start add the cancel button", "end add the cancel button", "start and a test for it", "end and a test for it"])
    }

    func testOpensAFolderWhereTheTitleSaysAndSaysSoWhenItCannot() async throws {
        final class Folders: Presenter, @unchecked Sendable {
            var opened: [String] = []
            var works = true
            func live(session: String, host: DisplayHost?) async {}
            func open(_ host: DisplayHost?) async -> Bool { true }
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { .landed }
            func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
            func card(_ card: SummaryCard) async {}
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { .landed }
            func launch(_ command: String, in folder: String?) async -> Typed { .landed }
            func walk(_ walk: WalkCard) async {}
            func scan(_ agents: [AgentNode], title: String) async {}
            func trace(_ trace: TraceData, title: String) async {}
            func board(title: String) async {}
            func openFolder(_ path: String, in opener: FolderOpener) async -> Bool {
                opened.append("\(opener.rawValue) \(path)")
                return works
            }
        }
        let presenter = Folders()
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: []), speaker: speaker, key: PersonKey(),
            face: RecordingFace(), owner: MemoryOwner(nil), presenter: presenter
        )
        let folder = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_8","agent":"memnox","summary":"editor","at":"2026-10-01T00:00:00Z","display":"folder","title":"editor","sessionId":"folder","host":{"cwd":"shop"}}}"#).event)
        await conversation.handle(folder)
        XCTAssertEqual(presenter.opened, ["editor shop"])
        XCTAssertEqual(speaker.said, [])
        presenter.works = false
        await conversation.handle(folder)
        XCTAssertEqual(speaker.said, ["My apologies, I could not open that folder."])
    }

    func testSendsTheWordsFixedInATypedMessageToBeLearned() async throws {
        let link = ScriptedLink()
        link.answers["learn-words"] = [try line(#"{"id":1,"ok":true,"words":["sessions"]}"#)]
        let conversation = Conversation(
            link: link, speaker: RecordingSpeaker(), key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        await conversation.learn(typed: "check the surgeons", sent: "check the sessions")
        XCTAssertEqual(link.sent.last?.method, "learn-words")
        XCTAssertEqual(link.sent.last?.learned, [LearnedWord(heard: "surgeons", meant: "sessions")])
        // Nothing fixed, nothing sent.
        let before = link.sent.count
        await conversation.learn(typed: "check the sessions", sent: "check the sessions")
        XCTAssertEqual(link.sent.count, before)
    }

    func testOpensAFolderWhereTheTitleSaysAndSaysSoWhenItCannot() async throws {
        final class Folders: Presenter, @unchecked Sendable {
            var opened: [String] = []
            var works = true
            func live(session: String, host: DisplayHost?) async {}
            func open(_ host: DisplayHost?) async -> Bool { true }
            func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { .landed }
            func focus(session: String, host: DisplayHost?) async -> Typed { .landed }
            func card(_ card: SummaryCard) async {}
            func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { .landed }
            func launch(_ command: String, in folder: String?) async -> Typed { .landed }
            func walk(_ walk: WalkCard) async {}
            func scan(_ agents: [AgentNode], title: String) async {}
            func trace(_ trace: TraceData, title: String) async {}
            func board(title: String) async {}
            func openFolder(_ path: String, in opener: FolderOpener) async -> Bool {
                opened.append("\(opener.rawValue) \(path)")
                return works
            }
        }
        let presenter = Folders()
        let speaker = RecordingSpeaker()
        let conversation = Conversation(
            link: SlowLink(seconds: 0, answer: []), speaker: speaker, key: PersonKey(),
            face: RecordingFace(), owner: MemoryOwner(nil), presenter: presenter
        )
        let folder = try XCTUnwrap(try line(#"{"id":0,"ok":true,"event":{"kind":"show","subject":"dsp_8","agent":"memnox","summary":"editor","at":"2026-10-01T00:00:00Z","display":"folder","title":"editor","sessionId":"folder","host":{"cwd":"shop"}}}"#).event)
        await conversation.handle(folder)
        XCTAssertEqual(presenter.opened, ["editor shop"])
        XCTAssertEqual(speaker.said, [])
        presenter.works = false
        await conversation.handle(folder)
        XCTAssertEqual(speaker.said, ["My apologies, I could not open that folder."])
    }

    func testSendsTheWordsFixedInATypedMessageToBeLearned() async throws {
        let link = ScriptedLink()
        link.answers["learn-words"] = [try line(#"{"id":1,"ok":true,"words":["sessions"]}"#)]
        let conversation = Conversation(
            link: link, speaker: RecordingSpeaker(), key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        await conversation.learn(typed: "check the surgeons", sent: "check the sessions")
        XCTAssertEqual(link.sent.last?.method, "learn-words")
        XCTAssertEqual(link.sent.last?.learned, [LearnedWord(heard: "surgeons", meant: "sessions")])
        // Nothing fixed, nothing sent.
        let before = link.sent.count
        await conversation.learn(typed: "check the sessions", sent: "check the sessions")
        XCTAssertEqual(link.sent.count, before)
    }

    func testSendsTheWordsFixedInATypedMessageToBeLearned() async throws {
        let link = ScriptedLink()
        link.answers["learn-words"] = [try line(#"{"id":1,"ok":true,"words":["sessions"]}"#)]
        let conversation = Conversation(
            link: link, speaker: RecordingSpeaker(), key: PersonKey(), face: RecordingFace(), owner: MemoryOwner(nil)
        )
        await conversation.learn(typed: "check the surgeons", sent: "check the sessions")
        XCTAssertEqual(link.sent.last?.method, "learn-words")
        XCTAssertEqual(link.sent.last?.learned, [LearnedWord(heard: "surgeons", meant: "sessions")])
        // Nothing fixed, nothing sent.
        let before = link.sent.count
        await conversation.learn(typed: "check the sessions", sent: "check the sessions")
        XCTAssertEqual(link.sent.count, before)
    }
}
