import Foundation

/// A daemon made of the demo world in `shared/demo/power-user.json`, so every page of the window draws full for a
/// person judging the design. Nothing here reaches the real daemon: reads come from the fixture, a held call answered
/// is settled here alone, a write answers with its page as it stood, and what only a daemon can do says it is demo data.
public final class DemoLink: DaemonLink, @unchecked Sendable {
    private let world: DemoJSON
    private let now: () -> Date
    private let lock = NSLock()
    private var settled: Set<String> = []
    private var listeners: [Int: AsyncThrowingStream<DaemonResponse, Error>.Continuation] = [:]
    private var nextListener = 0

    /// The person the demo is signed in as, for the cloud credential beside it.
    public let personName: String
    /// What a refused press says, so a page shows why nothing happened.
    public let demoOnly: String

    public init(fixture: Data, now: @escaping () -> Date = Date.init) throws {
        self.now = now
        world = try JSONDecoder().decode(DemoJSON.self, from: fixture).stamped(now: now())
        personName = world["answers"]?["person"]?["person"]?["name"]?.text ?? ""
        demoOnly = world["demoOnly"]?.text ?? ""
    }

    public func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        let method = DaemonMethod(rawValue: request.method)
        if method == .subscribe { return listen() }
        if method == .confirm, let subject = request.subject { settle(subject) }
        let lines = answers(request, method)
        return AsyncThrowingStream { continuation in
            for line in lines {
                do {
                    continuation.yield(try Self.response(line, id: request.id))
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
            }
            continuation.finish()
        }
    }

    /// Every piece of the fixture as the line the app would decode, named for the test that checks each one decodes.
    public func everyLine() -> [(name: String, line: DemoJSON)] {
        var lines = world["answers"]?.fields.sorted { $0.key < $1.key }.map { (name: $0.key, line: $0.value) } ?? []
        for event in (world["held"]?.items ?? []) + (world["notices"]?.items ?? []) {
            lines.append((name: "event \(event["subject"]?.text ?? "")", line: Self.ok.with("event", event)))
        }
        for (id, view) in world["sessionViews"]?.fields ?? [:] {
            lines.append((name: "session-view \(id)", line: Self.ok.with("session", view)))
        }
        lines.append((name: "memory", line: Self.ok.with("memoryFacts", Self.items(world["memory"]?.items ?? []))))
        return lines
    }

    /// The line one request is answered with, decoded the way the socket decodes it.
    public static func response(_ line: DemoJSON, id: Int) throws -> DaemonResponse {
        let encoder = JSONEncoder()
        let data = try encoder.encode(line.with("id", .number(Double(id))))
        return try JSONDecoder().decode(DaemonResponse.self, from: data)
    }

    private static let ok = DemoJSON.object(["ok": .bool(true)])

    /// The methods whose answer depends on what was asked or on what was answered here; the rest come from the fixture as written.
    private var asked: [DaemonMethod: (DemoLink, DaemonRequest) -> [DemoJSON]] {
        [
            .waiting: { link, _ in [DemoLink.ok.with("waiting", .array(link.waiting()))] },
            .home: { link, _ in
                let home = link.world["answers"]?["home"]?["home"]?.with("waiting", .number(Double(link.waiting().count)))
                return [home.map { DemoLink.ok.with("home", $0) } ?? DemoLink.ok]
            },
            .sessionView: { link, request in [DemoLink.ok.with("session", link.sessionView(request.sessionId))] },
            .activity: { link, request in [DemoLink.ok.with("activity", .object(["rows": .array(link.activity(request.activityFilter))]))] },
            .decision: { link, request in [link.decision(request.decisionId)] },
            .memoryFacts: { link, request in
                [DemoLink.ok.with("memoryFacts", DemoLink.items(link.memory(status: request.memoryStatus ?? MemoryStatus.verified.rawValue, scope: request.memoryScope)))]
            },
            .memorySearch: { link, request in [DemoLink.ok.with("memoryFacts", DemoLink.items(link.search(request.memoryQuery ?? "", scope: request.memoryScope)))] },
            .memoryLearn: { link, _ in [DemoLink.ok.with("memoryLearn", DemoLink.items(link.learn()))] },
            .memoryReject: { link, _ in [DemoLink.ok.with("memoryLearn", DemoLink.items(link.learn()))] },
            .memoryEdit: { link, _ in [DemoLink.ok.with("memoryLearn", DemoLink.items(link.learn()))] },
            .memoryConfirm: { link, request in
                let item = (link.world["memory"]?.items ?? []).first { $0["id"]?.text == request.memoryItemId }
                let answer = DemoLink.ok.with("memoryLearn", DemoLink.items(link.learn()))
                return [item.map { answer.with("memoryItem", $0) } ?? answer]
            },
            .ask: { link, _ in
                [
                    DemoLink.ok.with("chunk", .object(["kind": .string(ChunkKind.text.rawValue), "text": .string(link.demoOnly)])),
                    DemoLink.ok.with("chunk", .object(["kind": .string(ChunkKind.done.rawValue)])),
                ]
            },
        ]
    }

    private func answers(_ request: DaemonRequest, _ method: DaemonMethod?) -> [DemoJSON] {
        if let method, let answer = asked[method] { return answer(self, request) }
        let read = world["answers"]?.fields ?? [:]
        if let answer = read[request.method] { return [answer] }
        if let page = world["writes"]?[request.method]?.text, let answer = read[page] { return [answer] }
        return [Self.ok]
    }

    /// Held calls and notices as a subscription opens with them, then kept open so an answer here settles its card.
    private func listen() -> AsyncThrowingStream<DaemonResponse, Error> {
        let events = waiting() + (world["notices"]?.items ?? [])
        return AsyncThrowingStream { continuation in
            for event in events {
                if let response = try? Self.response(Self.ok.with("event", event), id: 0) { continuation.yield(response) }
            }
            let key = lock.withLock { () -> Int in
                nextListener += 1
                listeners[nextListener] = continuation
                return nextListener
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.listeners.removeValue(forKey: key) }
            }
        }
    }

    private func settle(_ subject: String) {
        guard let call = (world["held"]?.items ?? []).first(where: { $0["subject"]?.text == subject }) else { return }
        let listening = lock.withLock { () -> [AsyncThrowingStream<DaemonResponse, Error>.Continuation] in
            settled.insert(subject)
            return Array(listeners.values)
        }
        let event = DemoJSON.object([
            "kind": .string(EventKind.settled.rawValue), "subject": .string(subject), "agent": call["agent"] ?? .string(""),
            "summary": call["summary"] ?? .string(""), "at": .string(DemoTime.iso(now())),
        ])
        guard let response = try? Self.response(Self.ok.with("event", event), id: 0) else { return }
        for listener in listening { listener.yield(response) }
    }

    private func waiting() -> [DemoJSON] {
        let gone = lock.withLock { settled }
        return (world["held"]?.items ?? []).filter { !gone.contains($0["subject"]?.text ?? "") }
    }

    private func sessionView(_ id: String?) -> DemoJSON {
        let views = world["sessionViews"]?.fields ?? [:]
        return id.flatMap { views[$0] } ?? views.sorted { $0.key < $1.key }.first?.value ?? .null
    }

    private func rows() -> [DemoJSON] {
        world["answers"]?["activity"]?["activity"]?["rows"]?.items ?? []
    }

    /// The ledger narrowed as Activity and Today ask for it, by effect, agent, kind, words and time.
    private func activity(_ filter: ActivityFilter?) -> [DemoJSON] {
        guard let filter else { return rows() }
        let since = filter.since.flatMap(DemoTime.date)
        let until = filter.until.flatMap(DemoTime.date)
        return rows().filter { row in
            if let effect = filter.effect, row["effect"]?.text != effect { return false }
            if let agent = filter.agent, row["agent"]?.text != agent { return false }
            if let kind = filter.kind, row["kind"]?.text != kind { return false }
            if let text = filter.text, !text.isEmpty {
                let haystack = ["operation", "target", "rule"].compactMap { row[$0]?.text }.joined(separator: " ")
                if haystack.range(of: text, options: .caseInsensitive) == nil { return false }
            }
            let at = row["at"]?.text.flatMap(DemoTime.date)
            if let since, let at, at < since { return false }
            if let until, let at, at > until { return false }
            return true
        }
    }

    /// Why one ledger row went the way it did, built from the row itself.
    private func decision(_ id: String?) -> DemoJSON {
        guard let row = rows().first(where: { $0["id"]?.text == id }) ?? rows().first else { return Self.ok }
        let session = world["sessionViews"]?[row["session"]?.text ?? ""]
        var view: [String: DemoJSON] = [
            "row": row,
            "chain": .string("\(row["agentName"]?.text ?? "") for \(personName)"),
            "context": .array([]),
            "before": .array([]),
            "trace": .object(["mode": .string("shell"), "exitCode": .number(0), "durationMs": .number(840)]),
        ]
        if let rule = row["rule"] { view["rule"] = .object(["name": rule, "source": .string(RuleSource.person.rawValue), "decidedBy": .string(personName)]) }
        if let task = session?["task"] { view["task"] = task }
        return Self.ok.with("decision", .object(view))
    }

    private func memory(status: String, scope: String?) -> [DemoJSON] {
        (world["memory"]?.items ?? []).filter { item in
            item["status"]?.text == status && (scope == nil || item["scope"]?.text == scope)
        }
    }

    private func search(_ query: String, scope: String?) -> [DemoJSON] {
        (world["memory"]?.items ?? []).filter { item in
            (scope == nil || item["scope"]?.text == scope)
                && (item["statement"]?.text ?? "").range(of: query, options: .caseInsensitive) != nil
        }
    }

    /// What waits to be learned: the candidates and the conflicts.
    private func learn() -> [DemoJSON] {
        let open: Set<String> = [MemoryStatus.candidate.rawValue, MemoryStatus.conflicting.rawValue]
        return (world["memory"]?.items ?? []).filter { open.contains($0["status"]?.text ?? "") }
    }

    private static func items(_ items: [DemoJSON]) -> DemoJSON {
        .object(["items": .array(items), "more": .number(0)])
    }
}
