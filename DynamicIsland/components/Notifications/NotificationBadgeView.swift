import SwiftUI
import Defaults

struct NotificationBadgeView: View {
    @ObservedObject private var notificationBridge = NotificationBridgeManager.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @EnvironmentObject var vm: DynamicIslandViewModel

    @Default(.enableMerMotion) private var merMotionEnabled

    var body: some View {
        if merMotionEnabled && notificationBridge.unreadCount > 0 {
            badgeContent
        }
    }

    private var badgeContent: some View {
        HStack(spacing: 4) {
            Image(systemName: "bell.fill")
                .font(.system(size: 10))
                .foregroundColor(.white)

            Text(badgeText)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor)
        .clipShape(Capsule())
        .onTapGesture {
            coordinator.currentView = .notifications
            vm.open()
        }
    }

    private var badgeText: String {
        if notificationBridge.unreadCount > 99 {
            return "99+"
        }
        return "\(notificationBridge.unreadCount)"
    }

    private var badgeColor: Color {
        if let latest = notificationBridge.notifications.first {
            switch latest.type {
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
        return .blue
    }
}

// MARK: - Compact Badge (for minimalistic mode)

struct NotificationCompactBadge: View {
    @ObservedObject private var notificationBridge = NotificationBridgeManager.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @EnvironmentObject var vm: DynamicIslandViewModel

    @Default(.enableMerMotion) private var merMotionEnabled

    var body: some View {
        if merMotionEnabled && notificationBridge.unreadCount > 0 {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Text(notificationBridge.unreadCount > 9 ? "+" : "")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white)
                )
                .onTapGesture {
                    coordinator.currentView = .notifications
                    vm.open()
                }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        NotificationBadgeView()

        NotificationCompactBadge()
    }
    .padding()
    .background(Color.black)
}
