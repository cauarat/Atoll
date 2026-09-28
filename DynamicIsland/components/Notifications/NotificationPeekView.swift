import SwiftUI
import Defaults

struct NotificationPeekView: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var notificationBridge = NotificationBridgeManager.shared

    @Default(.enableMerMotion) private var merMotionEnabled

    @State private var replyText = ""
    @State private var sendState: SendState = .idle
    @FocusState private var isReplyFocused: Bool

    private enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

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
                    .foregroundColor(Color(white: 0.65))
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
                            .foregroundColor(Color(white: 0.65))
                            .lineLimit(1)
                    }

                    Text(notification.body)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // Reply bar: the field takes the width, Open sits hard right.
            HStack(spacing: 10) {
                if canReply {
                    replyField
                } else {
                    Spacer(minLength: 0)
                }

                if latestNotification?.link != nil {
                    Button(action: openLink) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 11))
                            Text("Open")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accentColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.85))
    }

    private var replyField: some View {
        HStack(spacing: 8) {
            TextField(replyPlaceholder, text: $replyText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .focused($isReplyFocused)
                .disabled(sendState == .sending)
                .onSubmit(send)

            if case .sending = sendState {
                ProgressView().controlSize(.small)
            } else if case .sent = sendState {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
            } else if case .failed(let reason) = sendState {
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(isReplyFocused ? 0.14 : 0.08))
        )
        .frame(maxWidth: .infinity)
        // The peek hides on a timer that knows nothing about what the user is
        // doing; without this it vanishes mid-sentence.
        .onChange(of: isReplyFocused) { _, focused in
            if focused {
                coordinator.holdSneakPeek()
            } else {
                coordinator.releaseSneakPeek()
            }
        }
        .onExitCommand { dismiss() }
    }

    private var replyPlaceholder: String {
        guard let sender = latestNotification?.sender, !sender.isEmpty else {
            return String(localized: "Reply…")
        }
        return String(localized: "Reply to \(sender)…")
    }

    private var canReply: Bool {
        NotificationSource.supportsReply(latestNotification?.source)
            && latestNotification?.channelID != nil
    }

    private func send() {
        guard let notification = latestNotification,
              let channelID = notification.channelID
        else { return }

        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, sendState != .sending else { return }

        sendState = .sending
        Task { @MainActor in
            do {
                try await MattermostClient.shared.sendMessage(channelID: channelID, message: text)
                replyText = ""
                sendState = .sent
                notificationBridge.markAsRead(notification.id)
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            } catch {
                // The text stays in the field. Losing what someone typed because
                // the network blinked is worse than the failure itself.
                sendState = .failed(
                    (error as? MattermostClient.ClientError)?.text
                        ?? String(localized: "Could not send")
                )
            }
        }
    }

    private func openLink() {
        if let url = latestNotification?.link {
            NSWorkspace.shared.open(url)
        }
        if let id = latestNotification?.id {
            notificationBridge.markAsRead(id)
        }
        dismiss()
    }

    private func dismiss() {
        isReplyFocused = false
        coordinator.releaseSneakPeek(after: 0.1)
        coordinator.toggleSneakPeek(status: false, type: coordinator.sneakPeek.type)
    }

    private var disabledView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 24))
                .foregroundColor(Color(white: 0.65))

            Text("MerMotion Disabled")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(white: 0.65))

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
        NotificationSource.displayName(for: latestNotification?.source)
    }

    private var iconForSource: String {
        NotificationSource.iconName(for: latestNotification?.source)
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
