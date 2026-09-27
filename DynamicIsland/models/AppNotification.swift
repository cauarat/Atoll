import Foundation

// MARK: - App Notification Model

struct AppNotification: Identifiable, Codable, Equatable {
    let id: String
    let type: NotificationType
    let sender: String
    let senderAvatar: String?
    let channel: String?
    /// The channel's id, for replying. Optional because everything already in
    /// `notifications.json` predates it -- a non-optional here would make the
    /// decoder throw and drop the whole stored history on first launch.
    let channelID: String?
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
