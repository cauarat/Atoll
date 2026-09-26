import SwiftUI
import Defaults

struct NotificationsTabView: View {
    @ObservedObject private var notificationBridge = NotificationBridgeManager.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @EnvironmentObject var vm: DynamicIslandViewModel

    @Default(.enableMerMotion) private var merMotionEnabled

    var body: some View {
        VStack(spacing: 0) {
            if merMotionEnabled {
                notificationsContent
            } else {
                disabledStateView
            }
        }
    }

    private var notificationsContent: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()
                .opacity(0.3)

            // Notifications list
            if notificationBridge.notifications.isEmpty {
                emptyStateView
            } else {
                notificationsList
            }
        }
    }

    private var headerView: some View {
        HStack {
            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                if notificationBridge.unreadCount > 0 {
                    Text("\(notificationBridge.unreadCount) unread")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                // Test notification button
                Button(action: {
                    notificationBridge.addTestNotification()
                }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Send test notification")

                // Mark all as read
                if notificationBridge.unreadCount > 0 {
                    Button(action: {
                        notificationBridge.markAllAsRead()
                    }) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Mark all as read")
                }

                // Clear all
                if !notificationBridge.notifications.isEmpty {
                    Button(action: {
                        notificationBridge.clearAllNotifications()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all notifications")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(notificationBridge.notifications) { notification in
                    NotificationRowView(notification: notification)
                        .onTapGesture {
                            if let url = notification.link {
                                NSWorkspace.shared.open(url)
                                notificationBridge.markAsRead(notification.id)
                            }
                        }
                        .contextMenu {
                            Button(action: {
                                notificationBridge.markAsRead(notification.id)
                            }) {
                                Label("Mark as Read", systemImage: "checkmark.circle")
                            }

                            if notification.link != nil {
                                Button(action: {
                                    if let url = notification.link {
                                        NSWorkspace.shared.open(url)
                                        notificationBridge.markAsRead(notification.id)
                                    }
                                }) {
                                    Label("Open Link", systemImage: "arrow.up.forward")
                                }
                            }

                            Divider()

                            Button(role: .destructive, action: {
                                notificationBridge.removeNotification(notification.id)
                            }) {
                                Label("Remove", systemImage: "trash")
                            }
                        }

                    Divider()
                        .opacity(0.2)
                        .padding(.leading, 52)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "bell.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Notifications")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)

            Text("Notifications from your apps will appear here")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disabledStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bell.slash.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("MerMotion is Disabled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            Text("Enable MerMotion in Settings to receive\napp notifications in your Dynamic Island")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                coordinator.currentView = .home
                vm.open()
            }) {
                Text("Open Settings")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NotificationsTabView()
        .frame(width: 320, height: 400)
        .background(Color(NSColor.controlBackgroundColor))
}
