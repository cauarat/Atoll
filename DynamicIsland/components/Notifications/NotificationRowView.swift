import SwiftUI

struct NotificationRowView: View {
    let notification: AppNotification
    @ObservedObject private var notificationBridge = NotificationBridgeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // App icon/avatar
            ZStack {
                Circle()
                    .fill(iconBackgroundColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: notification.type.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(iconBackgroundColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 3) {
                // Sender and time
                HStack {
                    Text(notification.sender)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if !notification.isRead {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }

                    Spacer()

                    Text(notification.timeAgo)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Channel (if any)
                if let channel = notification.channel {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                            .font(.system(size: 9))

                        Text(channel)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(typeColor.opacity(0.8))
                    .lineLimit(1)
                }

                // Message body
                Text(notification.body)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .opacity(notification.isRead ? 0.7 : 1.0)
    }

    private var iconBackgroundColor: Color {
        typeColor.opacity(0.2)
    }

    private var typeColor: Color {
        switch notification.type {
        case .directMessage:
            return .blue
        case .mention:
            return .orange
        case .channel:
            return .gray
        case .generic:
            return .purple
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        NotificationRowView(notification: AppNotification(
            id: "1",
            type: .mention,
            sender: "John Doe",
            senderAvatar: nil,
            channel: "engineering",
            body: "Hey, can you review this PR when you get a chance?",
            timestamp: Date().addingTimeInterval(-300),
            source: "mattermost",
            link: nil,
            isRead: false
        ))

        Divider()

        NotificationRowView(notification: AppNotification(
            id: "2",
            type: .directMessage,
            sender: "Jane Smith",
            senderAvatar: nil,
            channel: nil,
            body: "Thanks for your help yesterday!",
            timestamp: Date().addingTimeInterval(-3600),
            source: "mattermost",
            link: URL(string: "https://example.com"),
            isRead: true
        ))
    }
    .frame(width: 320)
    .background(Color(NSColor.controlBackgroundColor))
}
