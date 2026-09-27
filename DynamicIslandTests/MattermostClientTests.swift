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
import Defaults
@testable import Atoll

final class MattermostClientTests: XCTestCase {

    // MARK: - Server URL

    func testNormalizesBrowserChannelURLToServerRoot() {
        // The address bar is what people copy, and it carries the web app's own
        // route. Keeping that path aimed every API call at a URL that 404s.
        XCTAssertEqual(
            MattermostClient.normalizedBaseURL("https://team.actuar.group/actuar-group/channels/town-square")?.absoluteString,
            "https://team.actuar.group"
        )
        XCTAssertEqual(
            MattermostClient.normalizedBaseURL("https://team.actuar.group/equipe/messages/@alguem")?.absoluteString,
            "https://team.actuar.group"
        )
        XCTAssertEqual(
            MattermostClient.normalizedBaseURL("https://team.actuar.group/equipe/pl/abc123")?.absoluteString,
            "https://team.actuar.group"
        )
    }

    func testNormalizesPreservesSubpathInstall() {
        // A Mattermost served under a sub-path is legitimate, so only the web
        // app route may be cut -- not the whole path.
        XCTAssertEqual(
            MattermostClient.normalizedBaseURL("https://host.example/mattermost/equipe/channels/geral")?.absoluteString,
            "https://host.example/mattermost"
        )
        XCTAssertEqual(
            MattermostClient.normalizedBaseURL("https://host.example/mattermost")?.absoluteString,
            "https://host.example/mattermost"
        )
    }

    func testNormalizesTrimsAndRejectsJunk() {
        XCTAssertEqual(
            MattermostClient.normalizedBaseURL("  https://team.actuar.group/  ")?.absoluteString,
            "https://team.actuar.group"
        )
        XCTAssertEqual(
            MattermostClient.normalizedBaseURL("http://localhost:8065")?.absoluteString,
            "http://localhost:8065"
        )
        XCTAssertNil(MattermostClient.normalizedBaseURL("team.actuar.group"))
        XCTAssertNil(MattermostClient.normalizedBaseURL(""))
        XCTAssertNil(MattermostClient.normalizedBaseURL("https://user:pw@team.actuar.group"))
    }

    // MARK: - Monitored channels

    func testMonitoredChannelMatching() {
        let original = Defaults[.mattermostMonitoredChannels]
        defer { Defaults[.mattermostMonitoredChannels] = original }

        // Empty is the default, and it means no channel ever alerts on its own.
        Defaults[.mattermostMonitoredChannels] = []
        XCTAssertFalse(MattermostClient.matchesMonitoredChannel(name: "financeiro", displayName: "Financeiro"))

        // Either the internal name or the display name may be typed, in any
        // case, with or without a leading '#'.
        Defaults[.mattermostMonitoredChannels] = ["#Financeiro"]
        XCTAssertTrue(MattermostClient.matchesMonitoredChannel(name: "financeiro", displayName: nil))
        XCTAssertTrue(MattermostClient.matchesMonitoredChannel(name: nil, displayName: "Financeiro"))
        XCTAssertFalse(MattermostClient.matchesMonitoredChannel(name: "avisos", displayName: "Avisos Gerais"))

        Defaults[.mattermostMonitoredChannels] = ["Avisos Gerais"]
        XCTAssertTrue(MattermostClient.matchesMonitoredChannel(name: "avisos-gerais-interno", displayName: "avisos gerais"))
    }

    // MARK: - Body

    func testBodyFallsBackToAttachmentAndDropsEmpty() {
        XCTAssertEqual(MattermostClient.body(for: makePost(message: "  olá  ")), "olá")

        // An attachment-only post has no text; a blank peek would say nothing.
        XCTAssertEqual(
            MattermostClient.body(for: makePost(message: "", fileIDs: ["f1"])),
            String(localized: "📎 Sent a file")
        )

        // Neither text nor files: nothing worth showing.
        XCTAssertNil(MattermostClient.body(for: makePost(message: "   ")))
    }

    // MARK: - Wire format

    func testDecodesPostNestedAsAJSONString() throws {
        // data.post arrives as a JSON *string*, not an object -- the classic
        // trip-up with this API.
        let envelope = #"""
        {"event":"posted","data":{"channel_type":"D","sender_name":"@ana",
         "post":"{\"id\":\"p1\",\"message\":\"oi\",\"user_id\":\"u2\",\"create_at\":1790000000000}"}}
        """#

        let event = try? JSONDecoder().decode(WireEvent.self, from: Data(envelope.utf8))
        XCTAssertEqual(event?.event, "posted")
        XCTAssertEqual(event?.data?.channel_type, "D")

        let postJSON = try XCTUnwrap(event?.data?.post)
        let post = try? JSONDecoder().decode(WirePost.self, from: Data(postJSON.utf8))
        XCTAssertEqual(post?.id, "p1")
        XCTAssertEqual(post?.message, "oi")
        // Milliseconds, not seconds.
        XCTAssertEqual(post?.create_at, 1_790_000_000_000)
    }

    // MARK: - Helpers

    private func makePost(
        message: String,
        fileIDs: [String]? = nil,
        type: String? = nil
    ) -> WirePost {
        WirePost(
            id: "p1",
            message: message,
            user_id: "u1",
            create_at: 1_790_000_000_000,
            type: type,
            file_ids: fileIDs,
            props: nil
        )
    }
}
