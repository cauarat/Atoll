//
//  MattermostClient.swift
//  DynamicIsland
//
//  Talks to a Mattermost server directly over its v4 WebSocket API.
//

import Foundation
import Combine
import Network
import AppKit
import Defaults

/// Connects to a Mattermost server and turns `posted` events into
/// ``AppNotification``s for ``NotificationBridgeManager``.
///
/// Atoll is the client here -- there is no helper daemon. Authentication is a
/// personal access token (or a session token), held in the Keychain by
/// ``MattermostTokenStore``.
@MainActor
final class MattermostClient: ObservableObject {
    static let shared = MattermostClient()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(username: String)
        case failed(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected {
        didSet {
            guard state != oldValue else { return }
            Defaults[.mattermostConnected] = state.isConnected
        }
    }

    // MARK: - Private state

    private var socket: URLSessionWebSocketTask?
    private var sessionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var currentUserID: String?
    private var baseURL: URL?
    private var attempt = 0
    private var isStopping = false
    private var observersInstalled = false

    /// team id -> url-safe team slug, for building permalinks.
    private var teamNames: [String: String] = [:]
    /// Any team the user belongs to. A DM carries no team id, but Mattermost's
    /// `/pl/` route resolves the post server-side, so any slug gets there.
    private var fallbackTeamName: String?

    private var pathMonitor: NWPathMonitor?
    private var pathIsSatisfied = true

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Lifecycle

    /// Connects only if a server and token have been entered. Called on launch
    /// and whenever the MerMotion toggles change, so it must be quiet when the
    /// feature is unconfigured.
    func connectIfConfigured() {
        guard Self.normalizedBaseURL(Defaults[.mattermostServerURL]) != nil,
              MattermostTokenStore.shared.hasToken
        else { return }

        guard !state.isConnected, state != .connecting else { return }
        connect()
    }

    /// Validates and connects using whatever is currently stored.
    func connect() {
        isStopping = false
        attempt = 0
        installSystemObserversIfNeeded()
        teardownSocket()

        guard let base = Self.normalizedBaseURL(Defaults[.mattermostServerURL]) else {
            state = .failed(String(localized: "Enter a valid server URL, including https://"))
            return
        }
        let token = MattermostTokenStore.shared.token
        guard !token.isEmpty else {
            state = .failed(String(localized: "Enter an access token"))
            return
        }

        baseURL = base
        state = .connecting
        startSession(base: base, token: token)
    }

    func disconnect() {
        isStopping = true
        teardownSocket()
        state = .disconnected
    }

    private func startSession(base: URL, token: String) {
        sessionTask = Task { [weak self] in
            await self?.runSession(base: base, token: token)
        }
    }

    private func teardownSocket() {
        reconnectTask?.cancel(); reconnectTask = nil
        pingTask?.cancel(); pingTask = nil
        sessionTask?.cancel(); sessionTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Sleep tears the socket down before the NIC goes, so wake starts clean
    /// instead of waiting out a TCP timeout.
    private func installSystemObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isStopping else { return }
                self.teardownSocket()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isStopping else { return }
                self.attempt = 0   // waking is not a failure
                self.connectIfConfigured()
            }
            .store(in: &cancellables)

        // NetworkConnectivityManager publishes HUD presentation state, where
        // `.hidden` means both "on Ethernet" and "offline, HUD expired", so it
        // cannot answer "is the network up". Watch the path directly.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                let regained = satisfied && !self.pathIsSatisfied
                self.pathIsSatisfied = satisfied

                guard !self.isStopping else { return }
                if regained {
                    self.attempt = 0
                    self.connectIfConfigured()
                } else if !satisfied {
                    self.teardownSocket()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.ebullioscopic.Atoll.mattermost.path", qos: .utility))
        pathMonitor = monitor
    }

    // MARK: - Session

    private func runSession(base: URL, token: String) async {
        // Validate first: a bad token gives a clear status code here, where the
        // socket would only close with an opaque error.
        let me: WireUser
        do {
            me = try await fetchMe(base: base, token: token)
        } catch let error as ClientError {
            handleFatal(error.text)
            return
        } catch {
            scheduleReconnect(reason: String(localized: "Server unreachable"))
            return
        }

        guard !Task.isCancelled else { return }
        currentUserID = me.id
        Defaults[.mattermostUsername] = me.username

        await loadTeams(base: base, token: token)   // best effort; only affects links

        guard !Task.isCancelled else { return }
        guard let wsURL = Self.websocketURL(from: base) else {
            handleFatal(String(localized: "Could not build a WebSocket URL for this server"))
            return
        }

        let task = session.webSocketTask(with: wsURL)
        socket = task
        task.resume()

        do {
            // The token goes in the challenge, not in an upgrade header: sending
            // both makes an auth failure ambiguous.
            let challenge: [String: Any] = [
                "seq": 1,
                "action": "authentication_challenge",
                "data": ["token": token]
            ]
            let data = try JSONSerialization.data(withJSONObject: challenge)
            try await task.send(.string(String(decoding: data, as: UTF8.self)))
        } catch {
            scheduleReconnect(reason: String(localized: "Could not authenticate"))
            return
        }

        guard !Task.isCancelled else { return }
        state = .connected(username: me.username)
        attempt = 0
        startPinging(task)

        await receiveLoop(task)
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text): handle(Data(text.utf8))
                case .data(let data): handle(data)
                @unknown default: break
                }
            } catch {
                guard !Task.isCancelled, !isStopping else { return }
                scheduleReconnect(reason: String(localized: "Connection lost"))
                return
            }
        }
    }

    /// Our own liveness check: a Wi-Fi drop can leave `receive()` hanging rather
    /// than throwing.
    private func startPinging(_ task: URLSessionWebSocketTask) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                task.sendPing { [weak self] error in
                    guard error != nil else { return }
                    Task { @MainActor [weak self] in
                        guard let self, !self.isStopping else { return }
                        self.scheduleReconnect(reason: String(localized: "Connection lost"))
                    }
                }
            }
        }
    }

    // MARK: - Reconnect

    /// Wrong or revoked credentials will not fix themselves. Stop, rather than
    /// hammer the server until it rate-limits us.
    private func handleFatal(_ reason: String) {
        teardownSocket()
        state = .failed(reason)
    }

    private func scheduleReconnect(reason: String) {
        guard !isStopping else { return }

        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        pingTask?.cancel(); pingTask = nil

        state = .failed(reason)
        guard pathIsSatisfied else { return }

        // 1, 2, 4, 8, 16, 30, 30 … seconds, jittered so a server restart does not
        // bring every client back in the same second.
        let backoff = min(pow(2.0, Double(attempt)), 30)
        let delay = backoff * Double.random(in: 1.0...1.3)
        attempt += 1

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.isStopping else { return }
            guard let base = self.baseURL else { return }
            let token = MattermostTokenStore.shared.token
            guard !token.isEmpty else { return }

            self.state = .connecting
            self.startSession(base: base, token: token)
        }
    }

    // MARK: - Event handling

    private func handle(_ data: Data) {
        let decoder = JSONDecoder()

        // The reply to the auth challenge carries seq_reply and no event.
        if let reply = try? decoder.decode(WireReply.self, from: data), reply.seq_reply != nil {
            if reply.status == "FAIL" {
                handleFatal(reply.error?.message ?? String(localized: "Authentication failed"))
            }
            return
        }

        guard let event = try? decoder.decode(WireEvent.self, from: data),
              event.event == "posted",
              let payload = event.data,
              let postJSON = payload.post,
              let post = try? decoder.decode(WirePost.self, from: Data(postJSON.utf8))
        else { return }

        // Your own messages must not pop your own notch.
        guard post.user_id != currentUserID else { return }
        // Joins, leaves, header changes. Without this every channel join pops.
        guard post.type?.hasPrefix("system_") != true else { return }

        let isDirect = payload.channel_type == "D" || payload.channel_type == "G"

        // Channel type first: a DM that also mentions you is a DM.
        let type: AppNotification.NotificationType
        if isDirect {
            type = .directMessage
        } else if mentionsCurrentUser(payload.mentions) {
            type = .mention
        } else {
            type = .channel
        }

        guard let body = Self.body(for: post) else { return }

        let sender = post.props?.override_username?.nilIfBlank
            ?? payload.sender_name?.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).nilIfBlank
            ?? String(localized: "Mattermost")

        let notification = AppNotification(
            id: post.id,
            type: type,
            sender: sender,
            senderAvatar: nil,
            channel: isDirect ? nil : payload.channel_display_name?.nilIfBlank,
            body: body,
            timestamp: Date(timeIntervalSince1970: TimeInterval(post.create_at) / 1000),
            source: "mattermost",
            link: permalink(teamID: payload.team_id, postID: post.id),
            isRead: false
        )

        NotificationBridgeManager.shared.ingest(notification)
    }

    /// An attachment-only post carries no text; a blank peek is worse than
    /// saying what happened. A post with neither text nor files is dropped.
    private static func body(for post: WirePost) -> String? {
        let message = post.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty { return message }

        let files = post.file_ids?.count ?? 0
        guard files > 0 else { return nil }
        return files == 1
            ? String(localized: "Sent a file")
            : String(localized: "Sent \(files) files")
    }

    private func mentionsCurrentUser(_ mentions: String?) -> Bool {
        guard let mentions, let me = currentUserID,
              let ids = try? JSONDecoder().decode([String].self, from: Data(mentions.utf8))
        else { return false }
        return ids.contains(me)
    }

    /// `{server}/{team}/pl/{post}`. A DM carries no team id, but the permalink
    /// route resolves the post regardless of which team slug is in the path.
    private func permalink(teamID: String?, postID: String) -> URL? {
        guard let base = baseURL else { return nil }
        let slug = teamID?.nilIfBlank.flatMap { teamNames[$0] } ?? fallbackTeamName
        guard let slug else { return nil }
        return base.appendingPathComponent(slug)
            .appendingPathComponent("pl")
            .appendingPathComponent(postID)
    }

    // MARK: - REST

    private func loadTeams(base: URL, token: String) async {
        var request = URLRequest(url: base.appendingPathComponent("api/v4/users/me/teams"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let teams = try? JSONDecoder().decode([WireTeam].self, from: data)
        else { return }

        teamNames = Dictionary(teams.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        fallbackTeamName = teams.first?.name
    }

    private func fetchMe(base: URL, token: String) async throws -> WireUser {
        var request = URLRequest(url: base.appendingPathComponent("api/v4/users/me"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(String(localized: "Unexpected response from server"))
        }

        // Status before decoding: a captive portal answers 200 with HTML.
        switch http.statusCode {
        case 200:
            guard let user = try? JSONDecoder().decode(WireUser.self, from: data) else {
                throw ClientError(String(localized: "That URL did not answer like a Mattermost server"))
            }
            return user
        case 401:
            throw ClientError(String(localized: "Token rejected — it may have expired"))
        case 403:
            throw ClientError(String(localized: "Personal access tokens are disabled on this server"))
        case 404:
            throw ClientError(String(localized: "No Mattermost API at that URL"))
        default:
            throw ClientError(String(localized: "Server returned \(http.statusCode)"))
        }
    }

    // MARK: - URLs

    static func normalizedBaseURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lowered = text.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { return nil }
        while text.hasSuffix("/") { text.removeLast() }

        guard let url = URL(string: text),
              url.host?.isEmpty == false,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil
        else { return nil }
        return url
    }

    private static func websocketURL(from base: URL) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = (base.scheme?.lowercased() == "http") ? "ws" : "wss"
        // Subpath installs (https://host/mattermost) keep their prefix.
        components.path = base.path + "/api/v4/websocket"
        return components.url
    }

    // MARK: - Errors

    private struct ClientError: Error {
        let text: String
        init(_ text: String) { self.text = text }
    }
}

// MARK: - Wire format

/// The server's reply to an action, e.g. the authentication challenge.
private struct WireReply: Decodable {
    let status: String?
    let seq_reply: Int?
    let error: WireError?

    struct WireError: Decodable {
        let message: String?
    }
}

/// A WebSocket event envelope.
private struct WireEvent: Decodable {
    let event: String?
    let data: EventData?

    struct EventData: Decodable {
        /// A JSON *string* holding the post -- it has to be decoded a second time.
        let post: String?
        /// Also a JSON string, an array of user ids. Absent when nobody is mentioned.
        let mentions: String?
        let channel_display_name: String?
        let channel_type: String?
        let sender_name: String?
        /// Empty for DMs and group DMs.
        let team_id: String?
    }
}

private struct WirePost: Decodable {
    let id: String
    let message: String
    let user_id: String
    /// Milliseconds since the epoch, not seconds.
    let create_at: Int
    /// "" for a user post, "system_*" for joins and leaves.
    let type: String?
    let file_ids: [String]?
    let props: WireProps?

    struct WireProps: Decodable {
        let override_username: String?
    }
}

private struct WireUser: Decodable {
    let id: String
    let username: String
}

private struct WireTeam: Decodable {
    let id: String
    /// The URL slug, not the display name.
    let name: String
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
