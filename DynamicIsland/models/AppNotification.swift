import Foundation

// MARK: - App Notification Model

struct AppNotification: Identifiable, Codable, Equatable {
    let id: String
    let type: NotificationType
    let sender: String
    let senderAvatar: String?
    let channel: String?
    let body: String
    let timestamp: Date
    let source: String  // "mattermost", "slack", etc.
    let link: URL?
    var isRead: Bool

    enum NotificationType: String, Codable {
        case directMessage = "dm"
        case mention = "mention"
        case channel = "channel"
        case generic = "generic"

        var displayName: String {
            switch self {
            case .directMessage: return "Direct Message"
            case .mention: return "Mention"
            case .channel: return "Channel"
            case .generic: return "Notification"
            }
        }

        var iconName: String {
            switch self {
            case .directMessage: return "person.fill"
            case .mention: return "at"
            case .channel: return "number"
            case .generic: return "bell.fill"
            }
        }
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Mattermost Alert Format (from mm-notify)

struct MattermostAlert: Codable {
    let type: String
    let sender: String
    let senderAvatar: String?
    let channel: String?
    let message: String
    let timestamp: Int  // Unix timestamp in seconds
    let link: String?

    func toAppNotification(source: String = "mattermost") -> AppNotification {
        let notificationType: AppNotification.NotificationType
        switch type {
        case "dm":
            notificationType = .directMessage
        case "mention":
            notificationType = .mention
        case "channel":
            notificationType = .channel
        default:
            notificationType = .generic
        }

        return AppNotification(
            id: UUID().uuidString,
            type: notificationType,
            sender: sender,
            senderAvatar: senderAvatar,
            channel: channel,
            body: message,
            timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            source: source,
            link: link.flatMap { URL(string: $0) },
            isRead: false
        )
    }
}

// MARK: - Notification Source Configuration

struct NotificationSource: Identifiable, Codable {
    let id: String  // "mattermost", "slack", etc.
    let name: String
    let iconName: String
    var isEnabled: Bool
    var isConnected: Bool
    var serverURL: String?
    var username: String?

    static let mattermost = NotificationSource(
        id: "mattermost",
        name: "Mattermost",
        iconName: "bubble.left.and.bubble.right.fill",
        isEnabled: true,
        isConnected: false,
        serverURL: nil,
        username: nil
    )

    static let slack = NotificationSource(
        id: "slack",
        name: "Slack",
        iconName: "number.square.fill",
        isEnabled: false,
        isConnected: false,
        serverURL: nil,
        username: nil
    )

    static let discord = NotificationSource(
        id: "discord",
        name: "Discord",
        iconName: "gamecontroller.fill",
        isEnabled: false,
        isConnected: false,
        serverURL: nil,
        username: nil
    )
}
