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

    var timeAgo: String { timeAgo(relativeTo: Date()) }

    /// How long ago this arrived, measured against a reference the caller owns.
    ///
    /// The card was reading "in 0s" for a message that had just landed: a chat
    /// server whose clock is milliseconds ahead of the Mac's stamps the message
    /// in the future, and the formatter reports that faithfully. Anything
    /// inside a minute, on either side of now, is simply now.
    func timeAgo(relativeTo reference: Date) -> String {
        let elapsed = reference.timeIntervalSince(timestamp)
        guard elapsed >= 60 else { return String(localized: "now") }
        return Self.relativeFormatter.localizedString(for: timestamp, relativeTo: reference)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
