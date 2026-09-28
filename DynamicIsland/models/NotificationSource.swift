//
//  NotificationSource.swift
//  DynamicIsland
//
//  The apps MerMotion can show notifications from.
//

import Foundation
import Defaults

/// Where a notification came from, and what the UI may do with it.
///
/// `AppNotification.source` is a free-form string, and the answers to "what is
/// this called", "which glyph" and "can it be replied to" were switched on that
/// string in four separate places that had drifted apart. Adding a source meant
/// finding all of them. They now ask here.
enum NotificationSource: String, CaseIterable, Identifiable {
    case mattermost
    case clickMassa = "clickmassa"
    case slack
    case discord

    var id: String { rawValue }

    /// Resolves the string stored on a notification. Unknown sources still get
    /// sensible defaults rather than disappearing.
    static func from(_ source: String?) -> NotificationSource? {
        guard let source else { return nil }
        return NotificationSource(rawValue: source.lowercased())
    }

    var displayName: String {
        switch self {
        case .mattermost: return "Mattermost"
        case .clickMassa: return "ClickMassa"
        case .slack: return "Slack"
        case .discord: return "Discord"
        }
    }

    var iconName: String {
        switch self {
        case .mattermost: return "bubble.left.and.bubble.right.fill"
        case .clickMassa: return "message.badge.filled.fill"
        case .slack: return "number.square.fill"
        case .discord: return "gamecontroller.fill"
        }
    }

    /// Whether the notification card may offer a reply box.
    ///
    /// Replying needs a send endpoint and a conversation id. Slack and Discord
    /// have neither here yet.
    var supportsReply: Bool {
        switch self {
        case .mattermost, .clickMassa: return true
        case .slack, .discord: return false
        }
    }

    /// The brand mark in the asset catalog, when there is one.
    ///
    /// The SF Symbol stays as the fallback: a source with no logo is still
    /// worth showing, and inventing a mark for one would be worse than a glyph.
    var logoAsset: String? {
        switch self {
        case .mattermost: return "MattermostLogo"
        case .clickMassa: return "ClickMassaLogo"
        case .slack, .discord: return nil
        }
    }

    /// Whether the mark is a single-colour silhouette to be tinted, or artwork
    /// with its own colours. Mattermost's mark is drawn white on dark, the way
    /// Mattermost draws it; ClickMassa's carries its own cyan.
    var logoIsTemplate: Bool {
        switch self {
        case .mattermost: return true
        case .clickMassa, .slack, .discord: return false
        }
    }

    /// Whether the user wants notifications from this source at all.
    var isEnabled: Bool {
        switch self {
        case .mattermost: return Defaults[.enableMattermostNotifications]
        case .clickMassa: return Defaults[.enableClickMassaNotifications]
        // No ingest exists for these yet, so nothing can arrive to gate.
        case .slack, .discord: return true
        }
    }

    // MARK: - Resolution helpers

    /// The glyph for a source string, including ones this enum does not know.
    static func iconName(for source: String?) -> String {
        from(source)?.iconName ?? "bell.fill"
    }

    /// The display name for a source string. An unrecognised source shows its
    /// own name capitalised rather than a placeholder.
    static func displayName(for source: String?) -> String {
        if let known = from(source) { return known.displayName }
        guard let source, !source.isEmpty else { return String(localized: "Notification") }
        return source.capitalized
    }

    static func supportsReply(_ source: String?) -> Bool {
        from(source)?.supportsReply ?? false
    }

    static func logoAsset(for source: String?) -> String? {
        from(source)?.logoAsset
    }

    static func logoIsTemplate(for source: String?) -> Bool {
        from(source)?.logoIsTemplate ?? false
    }

    /// An unknown source is not gated -- nothing can deliver one, and silently
    /// dropping it would be the harder failure to diagnose.
    static func isEnabled(_ source: String?) -> Bool {
        from(source)?.isEnabled ?? true
    }
}
