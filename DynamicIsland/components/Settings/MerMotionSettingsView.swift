import SwiftUI
import Defaults
import Combine

struct MerMotionSettingsView: View {
    @ObservedObject private var notificationBridge = NotificationBridgeManager.shared
    @ObservedObject private var mattermost = MattermostClient.shared

    @Default(.enableMerMotion) private var merMotionEnabled
    @Default(.merMotionDuration) private var merMotionDuration
    @Default(.merMotionPeekStyle) private var merMotionPeekStyle
    @Default(.enableMattermostNotifications) private var mattermostEnabled
    @Default(.mattermostServerURL) private var mattermostServerURL

    @State private var tokenInput: String = MattermostTokenStore.shared.token
    @State private var testNotificationSent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                Divider()

                mainToggleSection

                Divider()

                if merMotionEnabled {
                    displaySettingsSection

                    Divider()

                    appIntegrationsSection
                }
            }
            .padding()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bell.badge")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text("MerMotion")
                        .font(.system(size: 18, weight: .semibold))

                    Text("App Notifications in Dynamic Island")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Main Toggle

    private var mainToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $merMotionEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable MerMotion")
                        .font(.system(size: 14, weight: .medium))

                    Text("Show app notifications as popup in Dynamic Island")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)

            if !merMotionEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))

                    Text("Enable to see notifications from Mattermost and other apps")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            }
        }
    }

    // MARK: - Display Settings

    private var displaySettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            // Presentation style
            VStack(alignment: .leading, spacing: 6) {
                Picker("Notification Style", selection: $merMotionPeekStyle) {
                    ForEach(MerMotionPeekStyle.allCases) { style in
                        Text(style.localizedName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text("Compact shows one scrolling line under the notch. Full Card expands it with the sender, channel, message and buttons.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Duration slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Notification Duration")
                        .font(.system(size: 14))

                    Spacer()

                    Text("\(Int(merMotionDuration))s")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Slider(value: $merMotionDuration, in: 2...15, step: 1)
                    .tint(.blue)

                Text("How long the notification popup stays visible")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Test notification
            HStack {
                Button(action: {
                    notificationBridge.addTestNotification()
                    testNotificationSent = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        testNotificationSent = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: testNotificationSent ? "checkmark" : "play.fill")
                            .font(.system(size: 12))
                        Text(testNotificationSent ? "Sent!" : "Send Test Notification")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(testNotificationSent ? Color.green : Color.blue)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Text("Preview how notifications appear")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - App Integrations

    private var appIntegrationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Integrations")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            mattermostIntegrationSection
        }
    }

    private var mattermostIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with toggle and status
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mattermost")
                        .font(.system(size: 14, weight: .medium))

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)

                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: $mattermostEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if mattermostEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    // Server URL
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("https://mattermost.example.com", text: $mattermostServerURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .disabled(mattermost.state.isConnected)
                    }

                    // Personal access token
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Access Token")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        SecureField("Paste your token", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .disabled(mattermost.state.isConnected)

                        Text("In Mattermost: Profile → Security → Personal Access Tokens → Create. Your server admin has to enable them first.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("The token is kept in your macOS Keychain, never in preferences.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    connectionControls

                    if mattermost.state.isConnected {
                        HStack(spacing: 16) {
                            statBox(title: "Total", value: "\(notificationBridge.notifications.count)")
                            statBox(title: "Unread", value: "\(notificationBridge.unreadCount)")
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var connectionControls: some View {
        HStack(spacing: 10) {
            if mattermost.state.isConnected {
                Button("Disconnect") {
                    mattermost.disconnect()
                }
                .buttonStyle(.bordered)
            } else {
                Button(mattermost.state == .connecting ? "Connecting…" : "Connect") {
                    // The token has to reach the Keychain before the client reads it.
                    MattermostTokenStore.shared.setToken(tokenInput)
                    mattermost.connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    mattermost.state == .connecting
                    || mattermostServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if mattermost.state == .connecting {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Status

    private var statusColor: Color {
        switch mattermost.state {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        switch mattermost.state {
        case .connected(let username): return String(localized: "Connected as @\(username)")
        case .connecting: return String(localized: "Connecting…")
        // The actual reason, not a generic "Not connected".
        case .failed(let reason): return reason
        case .disconnected: return String(localized: "Not connected")
        }
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)

            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Preview

#Preview {
    MerMotionSettingsView()
        .frame(width: 450, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
}
