//
//  ClickMassaClient.swift
//  DynamicIsland
//
//  Listens to a ClickMassa tenant and turns customer messages into notifications.
//

import Foundation
import Combine
import Network
import AppKit
import Defaults

/// Connects to ClickMassa and forwards the messages that are actually yours.
///
/// The shape follows ``MattermostClient`` -- reconnect with backoff, an open
/// deadline, a generation counter, sleep/wake and path monitoring -- because
/// those were all learned the hard way once already.
///
/// What is different, and what makes or breaks this: **the socket carries the
/// whole tenant.** Every ticket in the company arrives here, belonging to every
/// agent. Notifying on all of it would open the notch dozens of times a minute.
/// ``shouldNotify(payload:)`` is the part that matters.
@MainActor
final class ClickMassaClient: ObservableObject {
    static let shared = ClickMassaClient()

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

    @Published private(set) var state: ConnectionState = .disconnected

    // MARK: - Timings, matching the Mattermost client's
    private static let pingInterval: TimeInterval = 30
    private static let openDeadline: TimeInterval = 20
    private static let backoffFloor: TimeInterval = 1
    private static let backoffCeiling: TimeInterval = 30

    // MARK: - Private state

    private var socket: SocketIOConnection?
    private var sessionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var openDeadlineTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var appURL: URL?
    private var attempt = 0
    private var isStopping = false
    private var observersInstalled = false
    private var generation = 0

    /// Who we are, from the login response. Without these the filter cannot run,
    /// which is why nothing is ingested before a successful sign-in.
    private var currentUserID: Int?
    private var tenantID: Int?
    private var queueNames: [Int: String] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Lifecycle

    var hasCredentials: Bool { ClickMassaTokenStore.shared.hasCredentials }

    func connectIfConfigured() {
        guard Self.normalizedAppURL(Defaults[.clickMassaServerURL]) != nil,
              ClickMassaTokenStore.shared.hasCredentials
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
        ClickMassaTokenStore.shared.clear()
        currentUserID = nil
        tenantID = nil
        queueNames = [:]
    }

    func disconnect() {
        isStopping = true
        generation += 1
        teardown()
        state = .disconnected
    }

    private func startAttempt() {
        teardown()

        guard let app = Self.normalizedAppURL(Defaults[.clickMassaServerURL]) else {
            state = .failed(String(localized: "Enter a valid server URL, including https://"))
            return
        }
        guard ClickMassaTokenStore.shared.hasCredentials else {
            state = .failed(String(localized: "Enter your email and password"))
            return
        }

        appURL = app
        state = .connecting

        generation += 1
        let gen = generation
        sessionTask = Task { [weak self] in
            await self?.runSession(app: app, generation: gen)
        }
    }

    private func teardown() {
        reconnectTask?.cancel(); reconnectTask = nil
        pingTask?.cancel(); pingTask = nil
        openDeadlineTask?.cancel(); openDeadlineTask = nil
        sessionTask?.cancel(); sessionTask = nil
        socket?.disconnect(); socket = nil
    }

    private func installSystemObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isStopping else { return }
                self.generation += 1
                self.teardown()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isStopping else { return }
                self.attempt = 0
                self.connectIfConfigured()
            }
            .store(in: &cancellables)
    }

    // MARK: - Session

    private func runSession(app: URL, generation gen: Int) async {
        let account: WireAccount
        do {
            account = try await signIn(app: app)
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
        currentUserID = account.userId
        tenantID = account.tenantId
        queueNames = Dictionary(
            (account.queues ?? []).map { ($0.id, $0.queue) },
            uniquingKeysWith: { first, _ in first }
        )
        ClickMassaTokenStore.shared.setSessionToken(account.token)

        guard let socketURL = Self.socketURL(app: app, token: account.token) else {
            handleFatal(String(localized: "Could not build a socket URL for this server"))
            return
        }

        let connection = SocketIOConnection(
            url: socketURL,
            // The token goes in the query too. Which of the two this build of
            // ClickMassa reads is not documented; sending both costs nothing.
            authPayload: ["token": account.token],
            session: session
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event, username: account.username, generation: gen)
            }
        }
        socket = connection
        connection.connect()

        startOpenDeadline(generation: gen)
    }

    private func handle(_ event: SocketIOConnection.ConnectionEvent, username: String, generation gen: Int) {
        guard gen == generation, !isStopping else { return }

        switch event {
        case .connected:
            openDeadlineTask?.cancel(); openDeadlineTask = nil
            attempt = 0
            state = .connected(username: username)
            startPinging(generation: gen)

        case .event(let name, let payload):
            // The tenant's own room: "{tenantId}:ticketList".
            guard let tenantID, name == "\(tenantID):ticketList" else { return }
            handleTicketList(payload)

        case .failed(let reason):
            scheduleReconnect(reason: reason)

        case .closed:
            scheduleReconnect(reason: String(localized: "Connection closed"))
        }
    }

    private func startOpenDeadline(generation gen: Int) {
        openDeadlineTask?.cancel()
        openDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.openDeadline))
            guard !Task.isCancelled, let self, !self.isStopping, gen == self.generation else { return }
            guard !self.state.isConnected else { return }
            self.scheduleReconnect(reason: String(localized: "Server did not answer"))
        }
    }

    private func startPinging(generation gen: Int) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pingInterval))
                guard !Task.isCancelled else { return }
                guard let self, gen == self.generation else { return }
                self.socket?.ping()
            }
        }
    }

    // MARK: - Reconnect

    private func handleFatal(_ reason: String) {
        generation += 1
        teardown()
        state = .failed(reason)
    }

    private func scheduleReconnect(reason: String) {
        guard !isStopping else { return }

        socket?.disconnect(); socket = nil
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

    // MARK: - Events

    private func handleTicketList(_ data: Data) {
        guard let envelope = try? JSONDecoder.clickMassa.decode(WireEnvelope.self, from: data),
              envelope.type == "chat:create",
              let payload = envelope.payload
        else { return }

        guard shouldNotify(payload: payload) else { return }
        guard let notification = makeNotification(from: payload) else { return }

        NotificationBridgeManager.shared.ingest(notification)
    }

    /// Whether a message deserves the notch.
    ///
    /// The socket carries every ticket in the tenant, so without this the notch
    /// would show the whole company's WhatsApp. Two ways in: the ticket is
    /// already yours, or it is waiting unclaimed in a queue you belong to.
    func shouldNotify(payload: WireMessage) -> Bool {
        Self.shouldNotify(
            payload: payload,
            userID: currentUserID,
            queueIDs: Set(queueNames.keys)
        )
    }

    /// Pure so it can be tested against real frames, which matters more here than
    /// anywhere else in this client: get it wrong and the notch is either silent
    /// or shows the whole company's WhatsApp.
    nonisolated static func shouldNotify(payload: WireMessage, userID: Int?, queueIDs: Set<Int>) -> Bool {
        // `fromMe` is the company side, so this covers your own replies and
        // those of every colleague on the same conversation.
        guard payload.fromMe != true else { return false }
        guard let ticket = payload.ticket else { return false }
        // Without knowing who we are there is no "mine", and notifying on
        // everything would be worse than notifying on nothing.
        guard let userID else { return false }

        if ticket.userId == userID { return true }

        let unclaimed = ticket.userId == nil || ticket.status == "pending"
        if unclaimed, let queueId = ticket.queueId, queueIDs.contains(queueId) {
            return true
        }

        return false
    }

    private func makeNotification(from payload: WireMessage) -> AppNotification? {
        guard let body = Self.body(for: payload) else { return nil }

        let sender = payload.contact?.name?.nilIfBlank
            ?? payload.ticket?.contact?.name?.nilIfBlank
            ?? String(localized: "ClickMassa")

        // The queue is only worth showing when it is why you are being told --
        // on your own tickets it is noise.
        let isMine = payload.ticket?.userId == currentUserID
        let queueName = isMine ? nil : payload.ticket?.queueId.flatMap { queueNames[$0] }

        return AppNotification(
            id: payload.id,
            type: .directMessage,
            sender: sender,
            senderAvatar: nil,
            channel: queueName,
            channelID: payload.ticketId.map(String.init),
            body: body,
            timestamp: payload.createdAt ?? Date(),
            source: NotificationSource.clickMassa.rawValue,
            link: ticketLink(payload.ticketId),
            isRead: false
        )
    }

    /// An attachment carries no text; a blank card would say nothing.
    static func body(for payload: WireMessage) -> String? {
        let text = (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }

        guard let media = payload.mediaType, media != "text" else { return nil }
        return String(localized: "📎 Sent a file")
    }

    /// The login response lists `atendimento` among the account's routes, so the
    /// panel deep-links there. If that guess is wrong the Open button still lands
    /// on ClickMassa, which is no worse than not having a link.
    private func ticketLink(_ ticketId: Int?) -> URL? {
        guard let appURL else { return nil }
        guard let ticketId else { return appURL }
        return appURL.appendingPathComponent("atendimento").appendingPathComponent("\(ticketId)")
    }

    // MARK: - REST

    private func signIn(app: URL) async throws -> WireAccount {
        let store = ClickMassaTokenStore.shared
        guard let api = Self.apiURL(forApp: app) else {
            throw ClientError(String(localized: "Could not derive the API address from that URL"))
        }

        var request = URLRequest(url: api.appendingPathComponent("auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": store.email,
            "password": store.password
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError(String(localized: "Unexpected response from server"))
        }

        switch http.statusCode {
        case 200, 201:
            guard let account = try? JSONDecoder.clickMassa.decode(WireAccount.self, from: data) else {
                throw ClientError(String(localized: "Signed in, but could not read the account"))
            }
            return account
        case 401:
            throw ClientError(String(localized: "Wrong email or password"))
        case 403:
            throw ClientError(String(localized: "This account cannot sign in"))
        case 404:
            // The one inference in this client. A 404 means the sign-in route is
            // somewhere else on this build, and the message says so rather than
            // leaving it to guesswork.
            throw ClientError(String(localized: "No sign-in endpoint at /auth/login — the route may differ on this server"))
        default:
            throw ClientError(String(localized: "Server returned \(http.statusCode)"))
        }
    }

    // MARK: - URLs

    /// The address of the panel, as typed.
    static func normalizedAppURL(_ raw: String) -> URL? {
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
        components.path = ""
        return components.url
    }

    /// The API lives on a sibling host: the panel's first label gains `api`.
    /// `enterprise-419.clickmassa.com.br` → `enterprise-419api.clickmassa.com.br`,
    /// which is the host ClickMassa itself puts in the webhook URLs it hands out.
    static func apiURL(forApp app: URL) -> URL? {
        guard var components = URLComponents(url: app, resolvingAgainstBaseURL: false),
              let host = components.host
        else { return nil }

        var labels = host.split(separator: ".").map(String.init)
        guard let first = labels.first, !first.isEmpty else { return nil }
        labels[0] = first.hasSuffix("api") ? first : first + "api"
        components.host = labels.joined(separator: ".")
        return components.url
    }

    static func socketURL(app: URL, token: String) -> URL? {
        guard let api = apiURL(forApp: app),
              var components = URLComponents(url: api, resolvingAgainstBaseURL: false)
        else { return nil }

        components.scheme = (api.scheme?.lowercased() == "http") ? "ws" : "wss"
        components.path = "/socket.io/"
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket"),
            URLQueryItem(name: "token", value: token)
        ]
        return components.url
    }

    // MARK: - Errors

    struct ClientError: Error, LocalizedError {
        let text: String
        init(_ text: String) { self.text = text }
        var errorDescription: String? { text }
    }
}

// MARK: - Wire format

/// `{"type": "chat:create", "payload": {…}}`, the second element of the
/// `{tenantId}:ticketList` event.
struct WireEnvelope: Decodable {
    let type: String?
    let payload: WireMessage?
}

struct WireMessage: Decodable {
    let id: String
    let body: String?
    let fromMe: Bool?
    let mediaType: String?
    let ticketId: Int?
    let createdAt: Date?
    let ticket: WireTicket?
    let contact: WireContact?
}

struct WireTicket: Decodable {
    let id: Int?
    let status: String?
    /// Nil while nobody has picked the conversation up.
    let userId: Int?
    let queueId: Int?
    let contact: WireContact?
}

struct WireContact: Decodable {
    let id: Int?
    let name: String?
    let number: String?
}

private struct WireAccount: Decodable {
    let userId: Int
    let tenantId: Int
    let username: String
    let token: String
    let queues: [WireQueue]?

    struct WireQueue: Decodable {
        let id: Int
        let queue: String
    }
}

private extension JSONDecoder {
    /// ClickMassa sends ISO-8601 with fractional seconds (`…T15:49:16.256Z`).
    static let clickMassa: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = formatter.date(from: text) { return date }
            return ISO8601DateFormatter().date(from: text) ?? Date()
        }
        return decoder
    }()
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
