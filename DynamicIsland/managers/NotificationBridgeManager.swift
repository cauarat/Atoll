import Foundation
import Combine
import Defaults
import SwiftUI
import AppKit

@MainActor
final class NotificationBridgeManager: ObservableObject {
    static let shared = NotificationBridgeManager()

    // MARK: - Published Properties
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isMerMotionEnabled: Bool = true
    @Published private(set) var latestNotification: AppNotification?

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let maxNotifications = 50
    private var pollingTimer: Timer?

    // App Group configuration
    private let appGroupIdentifier = "group.com.cauatoledo.mmnotify"
    private let notificationsKey = "notifications"

    // MARK: - Initialization

    private init() {
        setupDefaultsObservation()
        loadNotificationsFromAppGroup()
        setupAppGroupPolling()
    }

    // MARK: - Setup

    private func setupDefaultsObservation() {
        // Observe MerMotion toggle changes
        Defaults.publisher(.enableMerMotion)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.isMerMotionEnabled = change.newValue
            }
            .store(in: &cancellables)
    }

    private func setupAppGroupPolling() {
        // Poll App Group every 2 seconds for new notifications
        // This is a fallback for when Darwin notifications aren't available
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadNotificationsFromAppGroup()
            }
        }
    }

    // MARK: - App Group Communication

    private func loadNotificationsFromAppGroup() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        var parsed: [AppNotification] = []

        // Try array of Data (JSON-encoded)
        if let data = userDefaults.array(forKey: notificationsKey) as? [Data] {
            for notificationData in data {
                if let notification = try? JSONDecoder().decode(AppNotification.self, from: notificationData) {
                    parsed.append(notification)
                }
            }
        }
        // Try array of JSON strings
        else if let jsonStrings = userDefaults.array(forKey: notificationsKey) as? [String] {
            for jsonString in jsonStrings {
                if let data = jsonString.data(using: .utf8) {
                    if let alert = try? JSONDecoder().decode(MattermostAlert.self, from: data) {
                        parsed.append(alert.toAppNotification())
                    } else if let notification = try? JSONDecoder().decode(AppNotification.self, from: data) {
                        parsed.append(notification)
                    }
                }
            }
        }

        if !parsed.isEmpty {
            updateNotifications(parsed)
        }
    }

    private func updateNotifications(_ newNotifications: [AppNotification]) {
        // Merge with existing notifications, avoiding duplicates
        var allNotifications = notifications

        for notification in newNotifications {
            if !allNotifications.contains(where: { $0.id == notification.id || ($0.sender == notification.sender && $0.body == notification.body && abs($0.timestamp.timeIntervalSince(notification.timestamp)) < 5) }) {
                allNotifications.insert(notification, at: 0)
            }
        }

        // Limit the number of notifications
        if allNotifications.count > maxNotifications {
            allNotifications = Array(allNotifications.prefix(maxNotifications))
        }

        notifications = allNotifications
        unreadCount = notifications.filter { !$0.isRead }.count

        // Show popup for latest notification
        if let latest = newNotifications.first {
            showNotificationPopup(latest)
        }

        // Update Mattermost connection status
        if !newNotifications.isEmpty {
            Defaults[.mattermostConnected] = true
        }
    }

    private func showNotificationPopup(_ notification: AppNotification) {
        guard isMerMotionEnabled else { return }

        latestNotification = notification

        // Show the notification popup in Dynamic Island
        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .appNotification(source: notification.source),
            duration: Defaults[.merMotionDuration],
            value: 0,
            icon: iconForSource(notification.source),
            title: notification.sender,
            subtitle: notification.channel ?? notification.body,
            accentColor: colorForType(notification.type)
        )
    }

    // MARK: - Public Methods

    func markAsRead(_ id: String) {
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index].isRead = true
            unreadCount = notifications.filter { !$0.isRead }.count
            saveToAppGroup()
        }
    }

    func markAllAsRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
        unreadCount = 0
        saveToAppGroup()
    }

    func removeNotification(_ id: String) {
        notifications.removeAll { $0.id == id }
        unreadCount = notifications.filter { !$0.isRead }.count
        saveToAppGroup()
    }

    func clearAllNotifications() {
        notifications.removeAll()
        unreadCount = 0
        saveToAppGroup()
    }

    func addTestNotification() {
        let testNotification = AppNotification(
            id: UUID().uuidString,
            type: .mention,
            sender: "Test User",
            senderAvatar: nil,
            channel: "general",
            body: "This is a test notification from MerMotion!",
            timestamp: Date(),
            source: "mattermost",
            link: URL(string: "https://example.com"),
            isRead: false
        )

        notifications.insert(testNotification, at: 0)
        unreadCount = notifications.filter { !$0.isRead }.count

        // Show the popup
        latestNotification = testNotification
        showNotificationPopup(testNotification)
    }

    // MARK: - Persistence

    private func saveToAppGroup() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        let data = notifications.map { notification -> Data? in
            try? JSONEncoder().encode(notification)
        }.compactMap { $0 }

        userDefaults.set(data, forKey: notificationsKey)
    }

    // MARK: - Helpers

    private func iconForSource(_ source: String) -> String {
        switch source {
        case "mattermost": return "bubble.left.and.bubble.right.fill"
        case "slack": return "number.square.fill"
        case "discord": return "gamecontroller.fill"
        default: return "bell.fill"
        }
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
