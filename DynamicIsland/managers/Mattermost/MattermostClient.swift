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
/// Atoll is the client here -- there is no helper daemon. The shape of this
/// follows mm-notify, which has been running against this server for months:
/// username and password rather than a personal access token, the same alert
/// scope, and the same socket hardening it arrived at the hard way.
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

    /// Lets mm-verificar-style self-testing work here too: a message you send
    /// yourself carrying this marker is allowed through, so the whole chain --
    /// server, socket, filter, notch, sound -- can be checked without needing
    /// another person to be around.
    nonisolated static let selfTestMarker = "[mm-notify-autoteste]"

    @Published private(set) var state: ConnectionState = .disconnected {
        didSet {
            guard state != oldValue else { return }
            Defaults[.mattermostConnected] = state.isConnected
        }
    }

    // MARK: - Timings, matching mm-notify's
    private static let pingInterval: TimeInterval = 30
    private static let openDeadline: TimeInterval = 20
    private static let backoffFloor: TimeInterval = 1
    private static let backoffCeiling: TimeInterval = 30

    // MARK: - Private state

    private var socket: URLSessionWebSocketTask?
    private var sessionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var openDeadlineTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var currentUserID: String?
    private var baseURL: URL?
    private var attempt = 0
    private var isStopping = false
    private var observersInstalled = false

    /// Every attempt gets a number, so events and timers belonging to a socket
    /// we have already walked away from cannot schedule a second reconnect.
    private var generation = 0

    private var teamNames: [String: String] = [:]
    private var fallbackTeamName: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Lifecycle

    var hasCredentials: Bool { MattermostTokenStore.shared.hasCredentials }

    /// Connects only if a server and credentials have been entered. Called on
    /// launch and whenever the MerMotion toggles change, so it stays quiet when
    /// the feature is unconfigured.
    func connectIfConfigured() {
        guard Self.normalizedBaseURL(Defaults[.mattermostServerURL]) != nil,
              MattermostTokenStore.shared.hasCredentials
        else { return }

        guard !state.isConnected, state != .connecting else { return }
        connect()
    }

    func connect() {
        isStopping = false
        attempt = 0
        installSystemObserversIfNeeded()
        startAttempt()
    }

    func signOut() {
        disconnect()
        MattermostTokenStore.shared.clear()
        Defaults[.mattermostUsername] = ""
        currentUserID = nil
    }

    func disconnect() {
        isStopping = true
        generation += 1          // orphan anything still in flight
        teardownSocket()
        state = .disconnected
    }

    private func startAttempt() {
        teardownSocket()

        guard let base = Self.normalizedBaseURL(Defaults[.mattermostServerURL]) else {
            state = .failed(String(localized: "Enter a valid server URL, including https://"))
            return
        }
        guard MattermostTokenStore.shared.hasCredentials else {
            state = .failed(String(localized: "Enter your username and password"))
            return
        }

        baseURL = base
        state = .connecting

        generation += 1
        let gen = generation
        sessionTask = Task { [weak self] in
            await self?.runSession(base: base, generation: gen)
        }
    }

    private func teardownSocket() {
        reconnectTask?.cancel(); reconnectTask = nil
        pingTask?.cancel(); pingTask = nil
        openDeadlineTask?.cancel(); openDeadlineTask = nil
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
                self.generation += 1
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
    }

    // MARK: - Session

    private func runSession(base: URL, generation gen: Int) async {
        let token: String
        let me: WireUser
        do {
            (token, me) = try await obtainSession(base: base)
        } catch let error as ClientError {
            guard gen == generation else { return }
            handleFatal(error.text)
            return
        } catch {
            guard gen == generation else { return }
            scheduleReconnect(reason: String(localized: "Server unreachable"))
            return
        }

        guard gen == generation, !Task.isCancelled else { return }
        currentUserID = me.id
        Defaults[.mattermostUsername] = me.username

        await loadTeams(base: base, token: token)   // best effort; only affects links

        guard gen == generation, !Task.isCancelled else { return }
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
            guard gen == generation else { return }
            scheduleReconnect(reason: String(localized: "Could not authenticate"))
            return
        }

        // Still `.connecting`: the state only becomes `.connected` on the
        // server's `hello`. Claiming success at this point would show a green
        // dot to someone whose password the server is about to reject.
        startOpenDeadline(generation: gen)

        await receiveLoop(task, generation: gen)
    }

    /// Reuse the stored session while it lasts; a Mattermost session is good for
    /// about a month, so logging in on every launch would be rude to the server.
    private func obtainSession(base: URL) async throws -> (String, WireUser) {
        let store = MattermostTokenStore.shared

        let stored = store.sessionToken
        if !stored.isEmpty, let user = try await fetchMe(base: base, token: stored) {
            return (stored, user)
        }

        return try await logIn(base: base)
    }

    private func logIn(base: URL) async throws -> (String, WireUser) {
        let store = MattermostTokenStore.shared
        guard store.hasCredentials else {
            throw ClientError(String(localized: "Enter your username and password"))
        }

        var request = URLRequest(url: base.appendingPathComponent("api/v4/users/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "login_id": store.loginID,
            "password": store.password
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(String(localized: "Unexpected response from server"))
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw ClientError(String(localized: "Wrong username or password"))
        case 403:
            throw ClientError(String(localized: "This account cannot sign in — it may be locked or need MFA"))
        case 404:
            throw ClientError(String(localized: "No Mattermost API at that URL"))
        default:
            throw ClientError(String(localized: "Server returned \(http.statusCode)"))
        }

        // The session token comes back in a header, not in the body. The body is
        // the User.
        guard let token = http.value(forHTTPHeaderField: "Token"), !token.isEmpty else {
            throw ClientError(String(localized: "Signed in, but the server sent no session token"))
        }
        guard let user = try? JSONDecoder().decode(WireUser.self, from: data) else {
            throw ClientError(String(localized: "That URL did not answer like a Mattermost server"))
        }

        MattermostTokenStore.shared.setSessionToken(token)
        return (token, user)
    }

    /// Returns nil when the token is no longer good, so the caller logs in again.
    private func fetchMe(base: URL, token: String) async throws -> WireUser? {
        var request = URLRequest(url: base.appendingPathComponent("api/v4/users/me"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(String(localized: "Unexpected response from server"))
        }

        switch http.statusCode {
        case 200:
            return try? JSONDecoder().decode(WireUser.self, from: data)
        case 401, 403:
            return nil          // expired or revoked; fall through to a fresh login
        case 404:
            throw ClientError(String(localized: "No Mattermost API at that URL"))
        default:
            throw ClientError(String(localized: "Server returned \(http.statusCode)"))
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask, generation gen: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard gen == generation else { return }
                switch message {
                case .string(let text): handle(Data(text.utf8), generation: gen)
                case .data(let data): handle(data, generation: gen)
                @unknown default: break
                }
            } catch {
                guard !Task.isCancelled, !isStopping, gen == generation else { return }
                scheduleReconnect(reason: String(localized: "Connection lost"))
                return
            }
        }
    }

    /// A socket can sit in CONNECTING forever after the Mac sleeps -- no open,
    /// no close, no error, just silence. Without this the client looks alive and
    /// receives nothing.
    private func startOpenDeadline(generation gen: Int) {
        openDeadlineTask?.cancel()
        openDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.openDeadline))
            guard !Task.isCancelled, let self, !self.isStopping, gen == self.generation else { return }
            guard !self.state.isConnected else { return }
            self.scheduleReconnect(reason: String(localized: "Server did not answer"))
        }
    }

    /// Our own liveness check: a Wi-Fi drop can leave `receive()` hanging rather
    /// than throwing.
    private func startPinging(_ task: URLSessionWebSocketTask, generation gen: Int) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pingInterval))
                guard !Task.isCancelled else { return }
                task.sendPing { [weak self] error in
                    guard error != nil else { return }
                    Task { @MainActor [weak self] in
                        guard let self, !self.isStopping, gen == self.generation else { return }
                        self.scheduleReconnect(reason: String(localized: "Connection lost"))
                    }
                }
            }
        }
    }

    // MARK: - Reconnect

    /// Wrong credentials will not fix themselves. Stop, rather than hammer the
    /// server until it rate-limits us.
    private func handleFatal(_ reason: String) {
        generation += 1
        teardownSocket()
        state = .failed(reason)
    }

    private func scheduleReconnect(reason: String) {
        guard !isStopping else { return }

        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        pingTask?.cancel(); pingTask = nil
        openDeadlineTask?.cancel(); openDeadlineTask = nil

        state = .failed(reason)

        let backoff = min(Self.backoffFloor * pow(2.0, Double(attempt)), Self.backoffCeiling)
        let delay = backoff * Double.random(in: 1.0...1.3)
        attempt += 1

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.isStopping else { return }
            self.startAttempt()
        }
    }

    // MARK: - Event handling

    private func handle(_ data: Data, generation gen: Int) {
        let decoder = JSONDecoder()

        if let reply = try? decoder.decode(WireReply.self, from: data),
           reply.event == nil,
           reply.status != nil || reply.error != nil {
            if reply.status == "FAIL" || reply.error != nil {
                // The stored session was refused. Drop it so the next attempt
                // logs in from the password instead of replaying a dead token.
                MattermostTokenStore.shared.setSessionToken("")
                handleFatal(reply.error?.message ?? String(localized: "Authentication failed"))
            }
            return
        }

        guard let event = try? decoder.decode(WireEvent.self, from: data) else { return }

        // Authentication is only confirmed by `hello`.
        if event.event == "hello" {
            openDeadlineTask?.cancel(); openDeadlineTask = nil
            attempt = 0
            state = .connected(username: Defaults[.mattermostUsername])
            if let socket { startPinging(socket, generation: gen) }
            return
        }

        guard event.event == "posted",
              let payload = event.data,
              let postJSON = payload.post,
              let post = try? decoder.decode(WirePost.self, from: Data(postJSON.utf8))
        else { return }

        guard let classified = classify(post: post, data: payload) else { return }
        guard let body = Self.body(for: post) else { return }

        let sender = post.props?.override_username?.nilIfBlank
            ?? payload.sender_name?.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).nilIfBlank
            ?? String(localized: "Mattermost")

        let isDirect = classified == .directMessage

        let notification = AppNotification(
            id: post.id,
            type: classified,
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

    /// Which messages are worth the notch, in mm-notify's order.
    ///
    /// The last rule is the one that matters most in daily use: a message in a
    /// channel you did not ask about is not an alert. Without it a busy
    /// workspace would open the notch all day.
    func classify(post: WirePost, data: WireEvent.EventData) -> AppNotification.NotificationType? {
        // Never alert on your own messages -- including ones sent from another
        // device, which arrive over this same socket. The self-test marker is
        // the single exception.
        if post.user_id == currentUserID {
            return post.message.contains(Self.selfTestMarker) ? .directMessage : nil
        }

        // Joins, leaves, topic changes.
        if post.type?.hasPrefix("system_") == true { return nil }

        if data.channel_type == "D" || data.channel_type == "G" { return .directMessage }

        if let mentions = data.mentions,
           let me = currentUserID,
           let ids = try? JSONDecoder().decode([String].self, from: Data(mentions.utf8)),
           ids.contains(me) {
            return .mention
        }

        if Self.matchesMonitoredChannel(name: data.channel_name, displayName: data.channel_display_name) {
            return .channel
        }

        return nil
    }

    /// Accepts the internal name or the display name, because the two are easy
    /// to mix up when typing a channel into settings.
    nonisolated static func matchesMonitoredChannel(name: String?, displayName: String?) -> Bool {
        let monitored = Defaults[.mattermostMonitoredChannels]
        guard !monitored.isEmpty else { return false }

        let targets = Set(monitored.map {
            $0.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        })

        if let name = name?.lowercased(), targets.contains(name) { return true }
        if let displayName = displayName?.lowercased(), targets.contains(displayName) { return true }
        return false
    }

    /// An attachment-only post carries no text; a blank peek is worse than
    /// saying what happened. A post with neither text nor files is dropped.
    nonisolated static func body(for post: WirePost) -> String? {
        let message = post.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty { return message }

        guard (post.file_ids?.count ?? 0) > 0 else { return nil }
        return String(localized: "📎 Sent a file")
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

    // MARK: - URLs

    /// Reduces whatever was pasted to the server root.
    ///
    /// People copy the address bar, which on Mattermost is a web-app route like
    /// `/{team}/channels/{name}`. Keeping that path would aim every API call at
    /// a URL that 404s, with nothing on screen explaining why. A sub-path
    /// install is still honoured -- only the web-app route is cut.
    nonisolated static func normalizedBaseURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lowered = text.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { return nil }
        while text.hasSuffix("/") { text.removeLast() }

        guard var components = URLComponents(string: text),
              components.host?.isEmpty == false,
              components.user == nil, components.password == nil
        else { return nil }

        components.query = nil
        components.fragment = nil

        var parts = components.path.split(separator: "/").map(String.init)
        // The web app's routes are /{team}/channels/…, /{team}/messages/… and
        // /{team}/pl/…, so the team slug goes with the marker.
        if let marker = parts.firstIndex(where: { $0 == "channels" || $0 == "messages" || $0 == "pl" }) {
            parts = Array(parts.prefix(max(0, marker - 1)))
        }
        components.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")

        guard let url = components.url else { return nil }
        return url
    }

    private static func websocketURL(from base: URL) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = (base.scheme?.lowercased() == "http") ? "ws" : "wss"
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

/// A reply to an action, e.g. the authentication challenge. It carries no
/// `event`, which is how it is told apart from a real event.
private struct WireReply: Decodable {
    let event: String?
    let status: String?
    let seq_reply: Int?
    let error: WireError?

    struct WireError: Decodable {
        let message: String?
    }
}

/// A WebSocket event envelope.
struct WireEvent: Decodable {
    let event: String?
    let data: EventData?

    struct EventData: Decodable {
        /// A JSON *string* holding the post -- it has to be decoded a second time.
        let post: String?
        /// Also a JSON string, an array of user ids. Absent when nobody is mentioned.
        let mentions: String?
        let channel_name: String?
        let channel_display_name: String?
        let channel_type: String?
        let sender_name: String?
        /// Empty for DMs and group DMs.
        let team_id: String?
    }
}

struct WirePost: Decodable {
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
