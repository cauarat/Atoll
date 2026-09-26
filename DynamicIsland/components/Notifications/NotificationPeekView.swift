import SwiftUI
import Defaults

struct NotificationPeekView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var notificationBridge = NotificationBridgeManager.shared

    @Default(.enableMerMotion) private var merMotionEnabled

    var body: some View {
        if merMotionEnabled {
            peekContent
        } else {
            disabledView
        }
    }

    private var peekContent: some View {
        VStack(spacing: 0) {
            // Header with app icon and name
            HStack(spacing: 8) {
                Image(systemName: iconForSource)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)

                Text(sourceName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Text(latestNotification?.timeAgo ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()
                .opacity(0.3)

            // Sender and message
            if let notification = latestNotification {
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.sender)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let channel = notification.channel {
                        Text(channel)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Text(notification.body)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // Action buttons
            HStack(spacing: 12) {
                // Mark as read button
                Button(action: {
                    if let id = latestNotification?.id {
                        notificationBridge.markAsRead(id)
                        coordinator.toggleSneakPeek(status: false, type: coordinator.sneakPeek.type)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 11))
                        Text("Dismiss")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Open link button
                if latestNotification?.link != nil {
                    Button(action: {
                        if let url = latestNotification?.link {
                            NSWorkspace.shared.open(url)
                            if let id = latestNotification?.id {
                                notificationBridge.markAsRead(id)
                            }
                            coordinator.toggleSneakPeek(status: false, type: coordinator.sneakPeek.type)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 11))
                            Text("Open")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(accentColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // View all button
                Button(action: {
                    coordinator.toggleSneakPeek(status: false, type: coordinator.sneakPeek.type)
                    coordinator.currentView = .notifications
                    vm.open()
                }) {
                    Text("View All")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.85))
    }

    private var disabledView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 24))
                .foregroundColor(.secondary)

            Text("MerMotion Disabled")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text("Enable in Settings")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private var latestNotification: AppNotification? {
        notificationBridge.latestNotification ?? notificationBridge.notifications.first
    }

    private var sourceName: String {
        guard let source = latestNotification?.source else { return "Notification" }
        switch source {
        case "mattermost": return "Mattermost"
        case "slack": return "Slack"
        case "discord": return "Discord"
        default: return source.capitalized
        }
    }

    private var iconForSource: String {
        guard let source = latestNotification?.source else { return "bell.fill" }
        switch source {
        case "mattermost": return "bubble.left.and.bubble.right.fill"
        case "slack": return "number.square.fill"
        case "discord": return "gamecontroller.fill"
        default: return "bell.fill"
        }
    }

    private var accentColor: Color {
        guard let type = latestNotification?.type else { return .blue }
        switch type {
        case .directMessage: return .blue
        case .mention: return .orange
        case .channel: return .gray
        case .generic: return .purple
        }
    }
}

// MARK: - Preview

#Preview {
    NotificationPeekView()
        .frame(width: 300, height: 150)
        .background(Color(NSColor.windowBackgroundColor))
}
