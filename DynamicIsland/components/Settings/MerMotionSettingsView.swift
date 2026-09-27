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
    @Default(.mattermostMonitoredChannels) private var monitoredChannels

    @Default(.merMotionSoundEnabled) private var soundEnabled
    @Default(.merMotionVolume) private var soundVolume
    @Default(.merMotionSoundDirectMessage) private var soundDirectMessage
    @Default(.merMotionSoundMention) private var soundMention
    @Default(.merMotionSoundChannel) private var soundChannel

    @State private var loginInput: String = MattermostTokenStore.shared.loginID
    @State private var passwordInput: String = ""
    @State private var newChannel: String = ""
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

                    soundSection

                    Divider()

                    appIntegrationsSection
                }
            }
            .padding()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
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

    // MARK: - Main toggle

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

    // MARK: - Display

    private var displaySettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

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
            }

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

    // MARK: - Sound

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sound")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Toggle(isOn: $soundEnabled) {
                Text("Play a sound")
                    .font(.system(size: 14))
            }
            .toggleStyle(.switch)

            if soundEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volume")
                            .font(.system(size: 14))
                        Spacer()
                        Text("\(Int(soundVolume * 100))%")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $soundVolume, in: 0...1)
                        .tint(.blue)

                    Text("Independent of the system volume.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                soundPicker("Direct message", selection: $soundDirectMessage)
                soundPicker("Mention", selection: $soundMention)
                soundPicker("Monitored channel", selection: $soundChannel)
            }
        }
    }

    private func soundPicker(_ label: LocalizedStringKey, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            ForEach(MerMotionSound.available, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    // MARK: - Integrations

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
                    credentialsSection
                    connectionControls

                    Divider()

                    monitoredChannelsSection

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

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Server URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("https://mattermost.example.com", text: $mattermostServerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(mattermost.state.isConnected)

                // Pasting the browser address bar is the common case, and what
                // gets used is not what was typed -- so show it.
                if let resolved = MattermostClient.normalizedBaseURL(mattermostServerURL),
                   resolved.absoluteString != mattermostServerURL.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Text("Will connect to \(resolved.absoluteString)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Username or email")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("you@example.com", text: $loginInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(mattermost.state.isConnected)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                SecureField("Your Mattermost password", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(mattermost.state.isConnected)

                Text("Kept in your macOS Keychain, never in preferences. A Mattermost session lasts about a month, and Atoll signs in again on its own when it expires.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connectionControls: some View {
        HStack(spacing: 10) {
            if mattermost.state.isConnected {
                Button("Sign Out") {
                    mattermost.signOut()
                    passwordInput = ""
                }
                .buttonStyle(.bordered)
            } else {
                Button(mattermost.state == .connecting ? "Signing in…" : "Sign In") {
                    MattermostTokenStore.shared.setCredentials(
                        loginID: loginInput,
                        password: passwordInput
                    )
                    // A new password invalidates whatever session was cached.
                    MattermostTokenStore.shared.setSessionToken("")
                    mattermost.connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    mattermost.state == .connecting
                    || mattermostServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || loginInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || passwordInput.isEmpty
                )
            }

            if mattermost.state == .connecting {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Monitored channels

    private var monitoredChannelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monitored channels")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Text("Direct messages and mentions always notify. A regular channel message only notifies if the channel is listed here.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                TextField("channel-name", text: $newChannel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit(addChannel)

                Button("Add", action: addChannel)
                    .buttonStyle(.bordered)
                    .disabled(newChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if monitoredChannels.isEmpty {
                Text("No channels — only direct messages and mentions.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ForEach(monitoredChannels, id: \.self) { channel in
                    HStack(spacing: 6) {
                        Image(systemName: "number")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text(channel)
                            .font(.system(size: 12))

                        Spacer()

                        Button {
                            monitoredChannels.removeAll { $0 == channel }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func addChannel() {
        let name = newChannel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !name.isEmpty else { return }
        guard !monitoredChannels.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            newChannel = ""
            return
        }
        monitoredChannels.append(name)
        newChannel = ""
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
        .frame(width: 450, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
}
