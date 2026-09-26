import SwiftUI
import Defaults
import Combine

struct MerMotionSettingsView: View {
    @ObservedObject private var notificationBridge = NotificationBridgeManager.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @EnvironmentObject var vm: DynamicIslandViewModel

    @Default(.enableMerMotion) private var merMotionEnabled
    @Default(.merMotionDuration) private var merMotionDuration
    @Default(.enableMattermostNotifications) private var mattermostEnabled
    @Default(.mattermostServerURL) private var mattermostServerURL
    @Default(.mattermostUsername) private var mattermostUsername
    @Default(.mattermostConnected) private var mattermostConnected

    @State private var testNotificationSent = false
    @State private var showConnectionTest = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Main toggle
                mainToggleSection

                Divider()

                // Notification display settings
                if merMotionEnabled {
                    displaySettingsSection

                    Divider()

                    // App integrations
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

            // Mattermost
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
                            .fill(mattermostConnected ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)

                        Text(mattermostConnected ? "Connected" : "Not connected")
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
                // Connection details
                VStack(alignment: .leading, spacing: 8) {
                    // Server URL
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("https://mattermost.example.com", text: $mattermostServerURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    }

                    // Username
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Username")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("username", text: $mattermostUsername)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    }

                    // Connection instructions
                    if !mattermostConnected {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                Text("Setup Required")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.orange)

                            Text("To receive Mattermost notifications, you need to run the mm-notify daemon with App Group support enabled.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(action: {
                                copySetupInstructions()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                    Text("Copy Setup Instructions")
                                        .font(.system(size: 12))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        // Connected info
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                            Text("Receiving notifications from Mattermost")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.secondary)

                        // Stats
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

    // MARK: - Helper Methods

    private func copySetupInstructions() {
        let instructions = """
        MerMotion Setup Instructions for mm-notify
        ===========================================

        1. Make sure the mm-notify daemon is running:
           cd /tmp/mattermost-notificator
           node src/index.js

        2. The daemon should automatically:
           - Write notifications to App Group UserDefaults
           - Send Darwin notifications to wake up Atoll

        3. Verify connection:
           - Open Atoll Settings > MerMotion
           - You should see "Connected" status

        For manual setup, ensure mm-notify writes to:
           App Group: group.com.cauatoledo.mmnotify
           Key: notifications
        """

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(instructions, forType: .string)
        #endif
    }
}

// MARK: - Preview

#Preview {
    MerMotionSettingsView()
        .frame(width: 450, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
}
