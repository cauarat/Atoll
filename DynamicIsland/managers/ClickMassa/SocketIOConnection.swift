//
//  SocketIOConnection.swift
//  DynamicIsland
//
//  Just enough Socket.IO to listen to ClickMassa.
//

import Foundation

/// A minimal Socket.IO v5 / Engine.IO v4 client over `URLSessionWebSocketTask`.
///
/// Only what ClickMassa needs: connect, join the default namespace, receive
/// events, answer pings. No acks, no binary, no rooms, no emitting. A full
/// Socket.IO dependency for one read-only listener would be a lot of surface for
/// very little.
///
/// The wire format, for whoever reads this next. Every frame is a digit or two
/// of prefix and then, optionally, JSON:
///
/// ```
/// 0{"sid":"…","pingInterval":25000}   Engine.IO OPEN, server → client
/// 40                                  Socket.IO CONNECT, client → server
/// 40{"sid":"…"}                       CONNECT accepted, server → client
/// 42["event",{…}]                     EVENT (this is the one that matters)
/// 2 / 3                               PING / PONG
/// ```
final class SocketIOConnection {
    enum ConnectionEvent {
        /// The namespace accepted us; events will follow.
        case connected
        /// An `EVENT` frame: the name, and the first argument as raw JSON.
        case event(name: String, payload: Data)
        case failed(String)
        case closed
    }

    private let url: URL
    private let session: URLSession
    private let authPayload: [String: Any]
    private let onEvent: (ConnectionEvent) -> Void

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var isStopping = false

    /// - Parameters:
    ///   - url: the socket.io endpoint, already carrying `EIO=4&transport=websocket`.
    ///   - authPayload: sent in the CONNECT frame. ClickMassa's family accepts the
    ///     token here or in the query string; passing it both ways costs nothing
    ///     and saves a round of guessing.
    init(
        url: URL,
        authPayload: [String: Any] = [:],
        session: URLSession = .shared,
        onEvent: @escaping (ConnectionEvent) -> Void
    ) {
        self.url = url
        self.authPayload = authPayload
        self.session = session
        self.onEvent = onEvent
    }

    // MARK: - Lifecycle

    func connect() {
        isStopping = false
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        receiveLoop = Task { [weak self] in
            await self?.listen(task)
        }
    }

    func disconnect() {
        isStopping = true
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// Keeps the socket honest. Engine.IO's own ping comes from the server, but a
    /// dropped Wi-Fi can leave `receive()` hanging rather than throwing.
    func ping() {
        task?.sendPing { _ in }
    }

    // MARK: - Receiving

    private func listen(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text): handle(text)
                case .data(let data): handle(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
            } catch {
                guard !Task.isCancelled, !isStopping else { return }
                onEvent(.failed(error.localizedDescription))
                return
            }
        }
    }

    private func handle(_ frame: String) {
        guard let first = frame.first else { return }

        switch first {
        case "0":
            // Engine.IO OPEN. Join the default namespace; the server answers 40.
            send(connectFrame())

        case "2":
            // Server ping. Engine.IO expects the pong or it drops us.
            send("3")

        case "4":
            handleSocketIOPacket(String(frame.dropFirst()))

        default:
            break
        }
    }

    private func handleSocketIOPacket(_ packet: String) {
        guard let type = packet.first else { return }
        let rest = String(packet.dropFirst())

        switch type {
        case "0":   // CONNECT accepted
            onEvent(.connected)

        case "1":   // DISCONNECT
            onEvent(.closed)

        case "4":   // CONNECT_ERROR
            onEvent(.failed(errorMessage(from: rest) ?? String(localized: "Connection refused")))

        case "2":   // EVENT
            handleEvent(rest)

        default:
            break
        }
    }

    /// `["name", payload]`, possibly preceded by an ack id (`42123[...]`).
    private func handleEvent(_ body: String) {
        let json = body.drop { $0.isNumber }
        guard let data = String(json).data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let name = array.first as? String
        else { return }

        let argument = array.count > 1 ? array[1] : [:]
        guard let payload = try? JSONSerialization.data(withJSONObject: argument) else { return }

        onEvent(.event(name: name, payload: payload))
    }

    private func errorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["message"] as? String
    }

    // MARK: - Sending

    private func connectFrame() -> String {
        guard !authPayload.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: authPayload)
        else { return "40" }
        return "40" + String(decoding: data, as: UTF8.self)
    }

    private func send(_ text: String) {
        task?.send(.string(text)) { _ in }
    }
}
