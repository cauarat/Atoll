/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import XCTest
@testable import Atoll

/// The frames here are shaped like the ones the real tenant emits. The filter is
/// the piece that decides between useful and unusable -- the socket carries every
/// ticket in the company -- so it is worth pinning down, and it is pure.
final class ClickMassaClientTests: XCTestCase {

    // MARK: - Rate limiting

    // 429 is what the server said when the client was signing in on every socket
    // reconnect. These pin down that the wait is read rather than guessed, and
    // that the message says what happened -- "Server returned 429" got read as a
    // rejected password, which is the one thing it does not mean.

    func testReadsRetryAfterInSeconds() {
        XCTAssertEqual(
            ClickMassaClient.retryDelay(retryAfter: "120", rateLimitReset: nil),
            120
        )
    }

    func testReadsRetryAfterAsHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let delay = ClickMassaClient.retryDelay(
            retryAfter: "Tue, 14 Nov 2023 22:18:20 GMT",   // now + 300
            rateLimitReset: nil,
            now: now
        )
        XCTAssertEqual(try XCTUnwrap(delay), 300, accuracy: 1)
    }

    func testFallsBackToRateLimitResetAsTimestamp() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let delay = ClickMassaClient.retryDelay(
            retryAfter: nil,
            rateLimitReset: "1700000060",
            now: now
        )
        XCTAssertEqual(try XCTUnwrap(delay), 60, accuracy: 1)
    }

    func testReadsRateLimitResetAsSecondsRemaining() {
        // The same header means a duration on plenty of servers.
        XCTAssertEqual(
            ClickMassaClient.retryDelay(retryAfter: nil, rateLimitReset: "45"),
            45
        )
    }

    func testNoHeadersMeansNoKnownWait() {
        XCTAssertNil(ClickMassaClient.retryDelay(retryAfter: nil, rateLimitReset: nil))
        XCTAssertNil(ClickMassaClient.retryDelay(retryAfter: "", rateLimitReset: "   "))
        XCTAssertNil(ClickMassaClient.retryDelay(retryAfter: "soon", rateLimitReset: nil))
    }

    func testRateLimitMessageSaysItIsNotThePassword() {
        // Whatever the server sends, the reader has to come away knowing their
        // password was never the problem.
        for delay in [nil, 0, 30, 600] as [TimeInterval?] {
            let message = ClickMassaClient.rateLimitMessage(retryAfter: delay)
            XCTAssertTrue(
                message.lowercased().contains("password"),
                "message for \(String(describing: delay)) never mentions the password: \(message)"
            )
            XCTAssertTrue(message.contains("Too many sign-in attempts"))
        }
    }

    func testRateLimitMessageRoundsTheWaitUp() {
        // 90 seconds is "2 minutes", never "1" -- a wait that reads as shorter
        // than it is invites the retry that deepens the block.
        XCTAssertTrue(ClickMassaClient.rateLimitMessage(retryAfter: 90).contains("2 minutes"))
        XCTAssertTrue(ClickMassaClient.rateLimitMessage(retryAfter: 601).contains("11 minutes"))
    }

    // MARK: - URLs

    func testDerivesAPIHostFromPanelHost() {
        // ClickMassa puts this very host in the webhook URLs it hands out.
        let app = try! XCTUnwrap(ClickMassaClient.normalizedAppURL("https://enterprise-419.clickmassa.com.br"))
        XCTAssertEqual(
            ClickMassaClient.apiURL(forApp: app)?.absoluteString,
            "https://enterprise-419api.clickmassa.com.br"
        )
    }

    func testDerivingAPIHostIsIdempotent() {
        // Someone pasting the API host itself should not get "…apiapi…".
        let app = try! XCTUnwrap(ClickMassaClient.normalizedAppURL("https://enterprise-419api.clickmassa.com.br"))
        XCTAssertEqual(
            ClickMassaClient.apiURL(forApp: app)?.absoluteString,
            "https://enterprise-419api.clickmassa.com.br"
        )
    }

    func testNormalizesPanelURL() {
        XCTAssertEqual(
            ClickMassaClient.normalizedAppURL("  https://enterprise-419.clickmassa.com.br/atendimento/1586555  ")?.absoluteString,
            "https://enterprise-419.clickmassa.com.br"
        )
        XCTAssertNil(ClickMassaClient.normalizedAppURL("enterprise-419.clickmassa.com.br"))
        XCTAssertNil(ClickMassaClient.normalizedAppURL(""))
    }

    func testSocketURLCarriesEngineIOParameters() {
        let app = try! XCTUnwrap(ClickMassaClient.normalizedAppURL("https://enterprise-419.clickmassa.com.br"))
        let socket = try! XCTUnwrap(ClickMassaClient.socketURL(app: app, token: "jwt"))

        XCTAssertEqual(socket.scheme, "wss")
        XCTAssertEqual(socket.host, "enterprise-419api.clickmassa.com.br")
        XCTAssertEqual(socket.path, "/socket.io/")

        let query = URLComponents(url: socket, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "EIO" }?.value, "4")
        XCTAssertEqual(query.first { $0.name == "transport" }?.value, "websocket")
        XCTAssertEqual(query.first { $0.name == "token" }?.value, "jwt")
    }

    // MARK: - Wire format

    func testDecodesChatCreateEnvelope() throws {
        let envelope = try JSONDecoder().decode(WireEnvelope.self, from: Data(Self.chatCreate.utf8))

        XCTAssertEqual(envelope.type, "chat:create")
        let payload = try XCTUnwrap(envelope.payload)
        XCTAssertEqual(payload.body, "Deu certo")
        XCTAssertEqual(payload.fromMe, false)
        XCTAssertEqual(payload.ticketId, 1586555)
        XCTAssertEqual(payload.contact?.name, "Physical Academia")
        XCTAssertEqual(payload.ticket?.userId, 14)
        XCTAssertEqual(payload.ticket?.queueId, 4)
    }

    func testTicketUpdateIsNotAMessage() throws {
        // The same event name carries ticket:update far more often than
        // chat:create; only the latter is a message.
        let envelope = try JSONDecoder().decode(
            WireEnvelope.self,
            from: Data(#"{"type":"ticket:update","payload":{"id":"x"}}"#.utf8)
        )
        XCTAssertEqual(envelope.type, "ticket:update")
    }

    // MARK: - Body

    func testBodyFallsBackForAttachmentsAndDropsEmptyText() {
        XCTAssertEqual(ClickMassaClient.body(for: Self.message(body: "  olá  ")), "olá")

        XCTAssertEqual(
            ClickMassaClient.body(for: Self.message(body: "", mediaType: "image")),
            String(localized: "📎 Sent a file")
        )

        XCTAssertNil(ClickMassaClient.body(for: Self.message(body: "   ", mediaType: "text")))
    }

    // MARK: - The filter

    /// Cauã is user 42 and belongs to queue 141 (Backoffice).
    private static let me = 42
    private static let myQueues: Set<Int> = [141]

    func testIgnoresOtherPeoplesConversations() throws {
        // Every frame the real tenant sent during the capture belonged to
        // someone else -- Marco (14) and Leonardo (36), queues 3 and 4. None of
        // them may open the notch.
        let payload = try XCTUnwrap(
            JSONDecoder().decode(WireEnvelope.self, from: Data(Self.chatCreate.utf8)).payload
        )
        XCTAssertFalse(
            ClickMassaClient.shouldNotify(payload: payload, userID: Self.me, queueIDs: Self.myQueues)
        )
    }

    func testNotifiesOnMyOwnTicket() {
        let payload = Self.message(body: "oi", ticketUserID: Self.me, queueID: 4)
        XCTAssertTrue(
            ClickMassaClient.shouldNotify(payload: payload, userID: Self.me, queueIDs: Self.myQueues)
        )
    }

    func testNotifiesOnUnclaimedTicketInMyQueue() {
        let waiting = Self.message(body: "oi", ticketUserID: nil, queueID: 141)
        XCTAssertTrue(
            ClickMassaClient.shouldNotify(payload: waiting, userID: Self.me, queueIDs: Self.myQueues)
        )

        let pending = Self.message(body: "oi", ticketUserID: 99, queueID: 141, status: "pending")
        XCTAssertTrue(
            ClickMassaClient.shouldNotify(payload: pending, userID: Self.me, queueIDs: Self.myQueues)
        )
    }

    func testIgnoresColleaguesTicketInMyQueue() {
        // Someone else already picked it up -- theirs to answer, not yours.
        let payload = Self.message(body: "oi", ticketUserID: 16, queueID: 141)
        XCTAssertFalse(
            ClickMassaClient.shouldNotify(payload: payload, userID: Self.me, queueIDs: Self.myQueues)
        )
    }

    func testIgnoresUnclaimedTicketInSomeoneElsesQueue() {
        let payload = Self.message(body: "oi", ticketUserID: nil, queueID: 3)
        XCTAssertFalse(
            ClickMassaClient.shouldNotify(payload: payload, userID: Self.me, queueIDs: Self.myQueues)
        )
    }

    func testIgnoresOurOwnOutboundMessages() {
        // `fromMe` is the company side: your replies and your colleagues'.
        let payload = Self.message(body: "resposta", ticketUserID: Self.me, queueID: 141, fromMe: true)
        XCTAssertFalse(
            ClickMassaClient.shouldNotify(payload: payload, userID: Self.me, queueIDs: Self.myQueues)
        )
    }

    func testIgnoresEverythingBeforeSignIn() {
        // No identity means no notion of "mine"; staying silent beats notifying
        // on the entire tenant.
        let payload = Self.message(body: "oi", ticketUserID: Self.me, queueID: 141)
        XCTAssertFalse(
            ClickMassaClient.shouldNotify(payload: payload, userID: nil, queueIDs: Self.myQueues)
        )
    }

    // MARK: - Helpers

    private static func message(
        body: String,
        mediaType: String = "text",
        ticketUserID: Int? = nil,
        queueID: Int? = nil,
        status: String = "open",
        fromMe: Bool = false
    ) -> WireMessage {
        let userField = ticketUserID.map(String.init) ?? "null"
        let queueField = queueID.map(String.init) ?? "null"
        let json = """
        {"id":"m1","body":\(jsonString(body)),"fromMe":\(fromMe),"mediaType":"\(mediaType)","ticketId":1,
         "ticket":{"id":1,"status":"\(status)","userId":\(userField),"queueId":\(queueField)}}
        """
        return try! JSONDecoder().decode(WireMessage.self, from: Data(json.utf8))
    }

    private static func jsonString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    /// Trimmed to the fields the client reads. The real frame carries the whole
    /// ticket, contact and connection graph.
    private static let chatCreate = """
    {"type":"chat:create","payload":{
      "id":"105e0792-8de8-480e-a1d0-b1d4b99b9f99",
      "body":"Deu certo",
      "fromMe":false,
      "mediaType":"text",
      "ticketId":1586555,
      "contact":{"id":7700,"name":"Physical Academia","number":"556298277428"},
      "ticket":{"id":1586555,"status":"open","userId":14,"queueId":4,
                "contact":{"id":7700,"name":"Physical Academia"}}
    }}
    """
}
