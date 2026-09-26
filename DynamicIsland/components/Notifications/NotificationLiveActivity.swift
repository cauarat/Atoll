import SwiftUI
import Defaults

struct NotificationLiveActivity: View {
    @ObservedObject var notificationBridgeManager = NotificationBridgeManager.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @State private var isHovering = false

    @Default(.enableMerMotion) private var merMotionEnabled

    var body: some View {
        if merMotionEnabled {
            notificationBadge
        } else {
            basicBadge
        }
    }

    private var notificationBadge: some View {
        HStack(spacing: 8) {
            // App icon based on source
            Image(systemName: iconForSource)
                .font(.system(size: 14))
                .foregroundColor(accentColor)

            // Sender name and count
            VStack(alignment: .leading, spacing: 0) {
                if let latest = latestNotification {
                    Text(latest.sender)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(latest.body)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }

            // Unread count badge
            if notificationBridgeManager.unreadCount > 1 {
                Text("\(notificationBridgeManager.unreadCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
                .overlay(
                    Capsule()
                        .stroke(accentColor.opacity(0.5), lineWidth: 1)
                )
        )
        .contentShape(Capsule())
        .onTapGesture {
            coordinator.currentView = .notifications
            vm.open()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    private var basicBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange)

            Text("\(notificationBridgeManager.unreadCount)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.3))
        )
        .contentShape(Capsule())
        .onTapGesture {
            coordinator.currentView = .notifications
            vm.open()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    private var latestNotification: AppNotification? {
        notificationBridgeManager.notifications.first
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
        guard let type = latestNotification?.type else { return .orange }
        switch type {
        case .directMessage: return .blue
        case .mention: return .orange
        case .channel: return .gray
        case .generic: return .purple
        }
    }

    @EnvironmentObject private var vm: DynamicIslandViewModel
}

#Preview {
    NotificationLiveActivity()
        .frame(width: 250, height: 60)
        .background(Color.black)
}
