import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The daemon's own sign in as the person: the code shown, asked about until approved, and signed out again.
final class DaemonSignInTests: XCTestCase {
    var link: ScriptedLink!
    var clock: Date!
    var slept: [TimeInterval] = []
    var signIn: DaemonSignIn!

    private let code = PersonSignInCode(userCode: "FYM6-FWDW", page: "https://app.memnox.com/apps/connect?code=FYM6-FWDW",
                                        expiresAt: 1_791_281_400_000)

    override func setUp() {
        link = ScriptedLink()
        // 2026-10-06T10:00:00Z, ten minutes before the code runs out.
        clock = Date(timeIntervalSince1970: 1_791_280_800)
        slept = []
        signIn = DaemonSignIn(link: link, now: { [unowned self] in self.clock },
                              sleep: { [unowned self] seconds in
                                  self.slept.append(seconds)
                                  self.clock = self.clock.addingTimeInterval(seconds)
                              })
    }

    func testBeginsNamingThisMacAndHandsBackTheCode() async throws {
        link.answers["person-sign-in"] = [try line(#"{"id":1,"ok":true,"person":{"signedIn":false,"code":{"userCode":"FYM6-FWDW","page":"https://app.memnox.com/apps/connect?code=FYM6-FWDW","expiresAt":1791281400000}}}"#)]
        let start = await signIn.begin(name: "Studio Mac")
        XCTAssertEqual(start, .started(code))
        XCTAssertEqual(link.sent.first?.method, "person-sign-in")
        XCTAssertEqual(link.sent.first?.name, "Studio Mac")
    }

    func testRidesOnTheAppsOwnCodeSoOneApprovalSignsBothIn() async throws {
        link.answers["person-sign-in"] = [try line(#"{"id":1,"ok":true,"person":{"signedIn":false,"code":{"userCode":"FYM6-FWDW","page":"https://app.memnox.com/apps/connect?code=FYM6-FWDW","expiresAt":1791281400000}}}"#)]
        _ = await signIn.begin(name: "Studio Mac", companionOf: "dc_app")
        XCTAssertEqual(link.sent.first?.companionOf, "dc_app")
        // A plain start carries none, so the daemon's own code is approved on its own as before.
        link.answers["person-sign-in"] = [try line(#"{"id":2,"ok":true,"person":{"signedIn":true,"name":"Ana"}}"#)]
        _ = await signIn.begin(name: "Studio Mac")
        XCTAssertNil(link.sent.last?.companionOf)
    }

    func testSaysWhoIsAlreadySignedInRatherThanStartingAgain() async throws {
        link.answers["person-sign-in"] = [try line(#"{"id":1,"ok":true,"person":{"signedIn":true,"name":"Ana"}}"#)]
        let start = await signIn.begin()
        XCTAssertEqual(start, .signedIn(name: "Ana"))
    }

    func testADaemonFromBeforeSignInIsSaidToBeTooOld() async throws {
        link.answers["person-sign-in"] = [try line(#"{"id":1,"ok":false,"error":"no method person-sign-in"}"#)]
        let start = await signIn.begin()
        XCTAssertEqual(start, .tooOld)
        link.answers["person"] = [try line(#"{"id":2,"ok":false,"error":"no method person"}"#)]
        let known = await signIn.isKnown()
        XCTAssertEqual(known, false)
        // A daemon that does not answer is down, not older, so nobody is sent to update it.
        link.unreachable = true
        let down = await signIn.isKnown()
        XCTAssertNil(down)
    }

    func testCarriesTheDaemonsReasonAndSaysWhenNothingAnswers() async throws {
        link.answers["person-sign-in"] = [try line(#"{"id":1,"ok":false,"error":"The control plane would not start a sign in."}"#)]
        let refused = await signIn.begin()
        XCTAssertEqual(refused, .refused("The control plane would not start a sign in."))
        link.unreachable = true
        let unreachable = await signIn.begin()
        XCTAssertEqual(unreachable, .unreachable)
    }

    func testWatchesUntilThePersonApprovedTheCode() async throws {
        link.answers["person"] = [
            try line(#"{"id":2,"ok":true,"person":{"signedIn":false,"code":{"userCode":"FYM6-FWDW","expiresAt":1791281400000}}}"#),
            try line(#"{"id":3,"ok":true,"person":{"signedIn":false,"code":{"userCode":"FYM6-FWDW","expiresAt":1791281400000}}}"#),
            try line(#"{"id":4,"ok":true,"person":{"signedIn":true,"name":"Ana","workspaceId":"ws_1"}}"#),
        ]
        let outcome = await watchOneByOne()
        XCTAssertEqual(outcome, .signedIn(name: "Ana"))
        XCTAssertEqual(slept, [DaemonSignIn.pollInterval, DaemonSignIn.pollInterval, DaemonSignIn.pollInterval])
    }

    func testWatchEndsWithTheDaemonsReasonWhenItsSignInStopped() async throws {
        link.answers["person"] = [try line(#"{"id":2,"ok":true,"person":{"signedIn":false,"failed":"The sign in was not approved (access_denied)."}}"#)]
        let outcome = await watchOneByOne()
        XCTAssertEqual(outcome, .failed("The sign in was not approved (access_denied)."))
    }

    func testWatchExpiresWithTheCode() async throws {
        link.answers["person"] = [try line(#"{"id":2,"ok":true,"person":{"signedIn":false,"code":{"userCode":"FYM6-FWDW","expiresAt":1791281400000}}}"#)]
        let outcome = await watchOneByOne()
        XCTAssertEqual(outcome, .expired)
        XCTAssertGreaterThanOrEqual(slept.count, 200)
    }

    func testConnectsThisMachineThroughTheMachineMethodsAndNamesTheWorkspace() async throws {
        let machine = DaemonSignIn(link: link, side: .machine)
        link.answers["machine-sign-in"] = [try line(#"{"id":1,"ok":true,"machine":{"signedIn":false,"code":{"userCode":"FYM6-FWDW","page":"https://app.memnox.com/apps/connect?code=FYM6-FWDW","expiresAt":1791281400000}}}"#)]
        let start = await machine.begin(name: "Studio Mac")
        XCTAssertEqual(start, .started(code))
        XCTAssertEqual(link.sent.first?.method, "machine-sign-in")
        XCTAssertEqual(link.sent.first?.name, "Studio Mac")
        link.answers["machine"] = [try line(#"{"id":2,"ok":true,"machine":{"signedIn":true,"name":"Viktor","workspaceId":"ws_1","machineId":"mch_1"}}"#)]
        let standing = await machine.standing()
        XCTAssertEqual(standing?.signedIn, true)
        XCTAssertEqual(standing?.name, "Viktor")
        XCTAssertEqual(link.sent.last?.method, "machine")
        link.answers["machine-sign-out"] = [try line(#"{"id":3,"ok":true,"machine":{"signedIn":false}}"#)]
        let out = await machine.signOut()
        XCTAssertTrue(out)
        XCTAssertEqual(link.sent.last?.method, "machine-sign-out")
    }

    func testAMachineConnectionTheWorkspaceLetGoIsSaidAsSuch() async throws {
        let machine = DaemonSignIn(link: link, side: .machine)
        link.answers["machine"] = [try line(#"{"id":1,"ok":true,"machine":{"signedIn":false,"failed":"The workspace let this machine go. Connect again to come back."}}"#)]
        let standing = await machine.standing()
        XCTAssertEqual(standing?.signedIn, false)
        XCTAssertEqual(standing?.failed, "The workspace let this machine go. Connect again to come back.")
    }

    func testSignOutAsksTheDaemonAndReportsWhetherItDid() async throws {
        link.answers["person-sign-out"] = [try line(#"{"id":1,"ok":true,"person":{"signedIn":false}}"#)]
        let out = await signIn.signOut()
        XCTAssertTrue(out)
        XCTAssertEqual(link.sent.last?.method, "person-sign-out")
    }

    /// The scripted link answers every scripted line to one request, so each poll is given its own answer.
    private func watchOneByOne() async -> DaemonSignInWatch {
        let scripted = link.answers["person"] ?? []
        let perPoll = PollingLink(answers: scripted)
        let polling = DaemonSignIn(link: perPoll, now: { [unowned self] in self.clock },
                                   sleep: { [unowned self] seconds in
                                       self.slept.append(seconds)
                                       self.clock = self.clock.addingTimeInterval(seconds)
                                   })
        return await polling.watch(code)
    }
}

/// A daemon that gives the next scripted answer to each request and repeats the last one after that.
private final class PollingLink: DaemonLink {
    private var answers: [DaemonResponse]
    init(answers: [DaemonResponse]) { self.answers = answers }

    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        let answer = answers.count > 1 ? answers.removeFirst() : answers.first
        return AsyncThrowingStream { continuation in
            if let answer { continuation.yield(answer) }
            continuation.finish()
        }
    }
}
