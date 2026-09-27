//
//  NotchNotificationsPanel.swift
//  DynamicIsland
//
//  App notifications in the column beside the music player.
//

import SwiftUI
import Defaults
import AppKit

/// The right-hand column of the open notch, when it is showing notifications
/// rather than the calendar.
///
/// Deliberately not `NotificationsTabView`: that one is built for the full-width
/// tab and colours itself with `.primary`/`.secondary`, which resolve against the
/// system appearance rather than the notch's fixed black — in Light Mode it
/// washes out. It also spends ~70pt on avatar and padding before any text, which
/// a ~280pt column cannot afford.
///
/// The row shape here is `EventListView`'s compact row, because that is what has
/// been living in these 120pt: a 3pt accent bar, a `.callout` title, and
/// `.caption` secondary text in `Color(white: 0.65)`.
struct NotchNotificationsPanel: View {
    @ObservedObject private var bridge = NotificationBridgeManager.shared
    @Default(.enableMerMotion) private var merMotionEnabled

    @State private var hoveredID: String?
    @State private var isHoveringHeader = false

    /// 120pt beside the music player, matching `CalendarView`'s cap — that cap
    /// is what keeps the notch window from growing. Standalone passes nil to
    /// fill instead.
    var fixedHeight: CGFloat? = 120

    var body: some View {
        VStack(spacing: 0) {
            header

            if bridge.notifications.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .frame(height: fixedHeight)
        .animation(.smooth(duration: 0.3), value: bridge.notifications.count)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("Notifications")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

            if bridge.unreadCount > 0 {
                Text("\(bridge.unreadCount)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }

            Spacer(minLength: 4)

            // Revealed on hover: a permanent button would spend column width on
            // something used once in a while.
            if isHoveringHeader && !bridge.notifications.isEmpty {
                Button {
                    bridge.clearAllNotifications()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.65))
                }
                .buttonStyle(.plain)
                .help("Clear all")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHoveringHeader = inside
            }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(bridge.notifications) { notification in
                    row(notification)

                    if notification.id != bridge.notifications.last?.id {
                        Divider()
                            .opacity(0.2)
                            // Past the accent bar, so the rule reads as a row
                            // separator rather than a full-width cut.
                            .padding(.leading, 7)
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func row(_ notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Rectangle()
                .fill(accent(for: notification.type))
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(notification.sender)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .layoutPriority(1)

                    if !notification.isRead {
                        Circle()
                            .fill(accent(for: notification.type))
                            .frame(width: 5, height: 5)
                    }

                    if let channel = notification.channel, !channel.isEmpty {
                        Text("#\(channel)")
                            .font(.caption)
                            .foregroundColor(Color(white: 0.65))
                            .lineLimit(1)
                    }
                }

                Text(notification.body)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.65))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // The dismiss button takes the timestamp's place on hover instead of
            // sitting beside it: in this width there is room for one, not both.
            Group {
                if hoveredID == notification.id {
                    Button {
                        bridge.removeNotification(notification.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.65))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                } else {
                    Text(notification.timeAgo)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .opacity(notification.isRead ? 0.65 : 1)
        .onHover { inside in
            hoveredID = inside ? notification.id : (hoveredID == notification.id ? nil : hoveredID)
        }
        .onTapGesture {
            if let url = notification.link {
                NSWorkspace.shared.open(url)
            }
            bridge.markAsRead(notification.id)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Empty

    /// Mirrors `EmptyEventsView` so the column reads the same whichever content
    /// is in it.
    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: merMotionEnabled ? "bell" : "bell.slash")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(Color(white: 0.65))
                .padding(.bottom, 7)

            Text(merMotionEnabled ? "No notifications" : "MerMotion is off")
                .font(.subheadline)
                .foregroundColor(.white)

            Text(merMotionEnabled ? "Messages will show up here" : "Turn it on in Settings")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
                .padding(.top, 1)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Colors

    /// The same mapping `NotificationBridgeManager.colorForType` uses for the
    /// peek, so a message keeps its colour between the closed and open notch.
    private func accent(for type: AppNotification.NotificationType) -> Color {
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
    NotchNotificationsPanel()
        .frame(width: 280)
        .padding()
        .background(Color.black)
}
