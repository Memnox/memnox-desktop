import AppKit
import Combine
import MemnoxVoiceCore
import UserNotifications

/// Says a new held call through the system's notifications when the island is not already showing it. It asks for
/// permission once, from the switch on Approvals or the first held call, never at launch, and a click opens Governance
/// on Approvals. It only says what waits; a yes is answered and signed on the island's card.
@MainActor
final class HeldNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = HeldNotifier()

    /// Whether the system refused, so the switch can say why nothing shows.
    @Published private(set) var refused = false
    @Published var on = UserDefaults.standard.object(forKey: HeldNotices.key) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(on, forKey: HeldNotices.key)
            if on { ask { _ in } }
        }
    }

    private var notices = HeldNotices()
    private var watching: AnyCancellable?

    /// An unbundled run, such as one from the package, has no notification center and would crash asking for it.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    private var asked: Bool {
        get { UserDefaults.standard.bool(forKey: HeldNotices.askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: HeldNotices.askedKey) }
    }

    /// Follows the island's waiting calls, read after each change has settled so the island's own mode is current.
    func watch(_ island: IslandModel?) {
        center?.delegate = self
        guard let island else {
            watching = nil
            return
        }
        watching = island.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak island] _ in
                guard let self, let island else { return }
                self.check(island)
            }
    }

    private func check(_ island: IslandModel) {
        let calls = island.waiting.entries.map { NoticeCall(subject: $0.subject, label: $0.card.who, what: $0.card.what) }
        // Only a held card on screen counts as shown; a call waiting behind the voice or a folded island is said.
        let onIsland = island.mode == .held ? island.waiting.shownSubject : nil
        // Every call is met even while the switch is off, so turning it on never says the old ones.
        let posted = notices.next(calls, onIsland: onIsland)
        guard on, !posted.isEmpty, center != nil else { return }
        ask { [weak self] granted in
            guard granted else { return }
            for notice in posted { self?.post(notice) }
        }
    }

    /// Asks the system once, and after that only reads what it answered.
    func ask(_ then: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let center else { return then(false) }
        if asked {
            center.getNotificationSettings { settings in
                let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                Task { @MainActor in
                    self.refused = !granted
                    then(granted)
                }
            }
            return
        }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.refused = !granted
                then(granted)
            }
        }
    }

    private func post(_ notice: HeldNotice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        center?.add(UNNotificationRequest(identifier: notice.subject, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
        Task { @MainActor in
            SettingsWindow.shared.show()
            AppWindow.shared.shell.go(HeldNotices.opens)
        }
    }

    /// Shown even while Memnox is in front, since the island may be folded away when a call is held.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
