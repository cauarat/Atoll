import Foundation
import Combine
import Defaults
import SwiftUI
import AppKit

/// The store and presenter for MerMotion app notifications.
///
/// This type owns *what* is shown and *when*; it does not talk to any chat
/// server. Sources push in through `ingest(_:)` -- today only
/// ``MattermostClient``, which is started and stopped from here so flipping a
/// settings toggle takes effect without a relaunch.
@MainActor
final class NotificationBridgeManager: ObservableObject {
    static let shared = NotificationBridgeManager()

    // MARK: - Published Properties
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var latestNotification: AppNotification?

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let maxNotifications = 50
    private var hasStarted = false

    /// The last notification actually shown in the notch, so a source that
    /// re-delivers something cannot make the same message pop twice.
    private var lastPresentedID: String?

    /// Restored history is a backlog, not news -- nothing pops until this is true.
    private var hasCompletedInitialLoad = false

    /// Belt to `lastPresentedID`'s braces: a source replaying old messages with
    /// fresh ids gets at most one stale pop instead of a rolling stream.
    private static let popupFreshnessWindow: TimeInterval = 120

    private static let storeURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("MerMotion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notifications.json")
    }()

    // MARK: - Initialization

    /// Deliberately inert. The singleton is held as an `AppDelegate` stored
    /// property, so it is constructed before the app has finished launching;
    /// everything with a side effect waits for `start()`.
    private init() {}

    // MARK: - Lifecycle

    /// Starts the bridge. Idempotent.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        loadPersisted()
        hasCompletedInitialLoad = true

        Defaults.publisher(.enableMerMotion)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncSources() }
            .store(in: &cancellables)

        Defaults.publisher(.enableMattermostNotifications)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncSources() }
            .store(in: &cancellables)

        syncSources()
    }

    func stop() {
        cancellables.removeAll()
        MattermostClient.shared.disconnect()
        ClickMassaClient.shared.disconnect()
        hasStarted = false
    }

    private func syncSources() {
        guard hasStarted else { return }

        if Defaults[.enableMerMotion] && Defaults[.enableMattermostNotifications] {
            MattermostClient.shared.connectIfConfigured()
        } else {
            MattermostClient.shared.disconnect()
        }

        if Defaults[.enableMerMotion] && Defaults[.enableClickMassaNotifications] {
            ClickMassaClient.shared.connectIfConfigured()
        } else {
            ClickMassaClient.shared.disconnect()
        }
    }

    // MARK: - Ingest

    /// Accepts a message from a source. Safe to call with something already held:
    /// duplicates are dropped by id and never re-pop.
    func ingest(_ notification: AppNotification) {
        ingest([notification])
    }

    func ingest(_ incoming: [AppNotification]) {
        let known = Set(notifications.map(\.id))
        let fresh = incoming
            .filter { !known.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }

        guard !fresh.isEmpty else { return }

        notifications = Array((fresh + notifications).prefix(maxNotifications))
        unreadCount = notifications.filter { !$0.isRead }.count
        persist()

        guard hasCompletedInitialLoad else { return }
        guard let latest = fresh.first,
              latest.id != lastPresentedID,
              latest.timestamp.timeIntervalSinceNow > -Self.popupFreshnessWindow
        else { return }

        showNotificationPopup(latest)
    }

    // MARK: - Presentation

    private func showNotificationPopup(_ notification: AppNotification) {
        guard Defaults[.enableMerMotion] else { return }
        guard NotificationSource.isEnabled(notification.source) else { return }

        latestNotification = notification
        lastPresentedID = notification.id

        MerMotionSound.play(for: notification.type)

        // The peek is one line, so the channel rides along with the sender and the
        // subtitle carries the message. Putting the channel in the subtitle instead
        // dropped the message entirely for anything posted in a channel.
        let title: String = {
            guard let channel = notification.channel, !channel.isEmpty else { return notification.sender }
            return "\(notification.sender) · #\(channel)"
        }()

        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .appNotification(source: notification.source),
            duration: Defaults[.merMotionDuration],
            value: 0,
            icon: iconForSource(notification.source),
            title: title,
            subtitle: Self.clamped(notification.body),
            accentColor: colorForType(notification.type)
        )
    }

    /// The peek scrolls its text once; an unclamped wall of text would still be
    /// scrolling long after the peek was meant to hide.
    private static func clamped(_ body: String) -> String {
        let collapsed = body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 200 else { return collapsed }
        return collapsed.prefix(199) + "…"
    }

    // MARK: - Public Methods

    func markAsRead(_ id: String) {
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index].isRead = true
            unreadCount = notifications.filter { !$0.isRead }.count
            persist()
        }
    }

    func markAllAsRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
        unreadCount = 0
        persist()
    }

    func removeNotification(_ id: String) {
        notifications.removeAll { $0.id == id }
        unreadCount = notifications.filter { !$0.isRead }.count
        persist()
    }

    func clearAllNotifications() {
        notifications.removeAll()
        unreadCount = 0
        latestNotification = nil
        persist()
    }

    func addTestNotification(source: NotificationSource = .mattermost) {
        // A fresh id every press: each press really is a new notification, and it
        // must get past the duplicate check that real messages go through.
        let testNotification = AppNotification(
            id: UUID().uuidString,
            type: .mention,
            sender: "Test User",
            senderAvatar: nil,
            channel: source == .mattermost ? "general" : nil,
            channelID: nil,
            body: "This is a test notification from MerMotion!",
            timestamp: Date(),
            source: source.rawValue,
            link: nil,
            isRead: false
        )

        ingest(testNotification)
    }

    // MARK: - Persistence

    private func loadPersisted() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let stored = try? JSONDecoder().decode([AppNotification].self, from: data)
        else { return }

        notifications = Array(stored.prefix(maxNotifications))
        unreadCount = notifications.filter { !$0.isRead }.count
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notifications) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }

    // MARK: - Helpers

    private func iconForSource(_ source: String) -> String {
        NotificationSource.iconName(for: source)
    }

    private func colorForType(_ type: AppNotification.NotificationType) -> Color {
        switch type {
        case .directMessage: return .blue
        case .mention: return .orange
        case .channel: return .gray
        case .generic: return .purple
        }
    }
}
