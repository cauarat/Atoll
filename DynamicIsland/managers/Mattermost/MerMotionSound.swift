//
//  MerMotionSound.swift
//  DynamicIsland
//
//  The alert sound for app notifications.
//

import AppKit
import Defaults

/// Plays the per-type alert sound, the way mm-notify's popup does.
///
/// These are macOS system sounds loaded by name out of `/System/Library/Sounds`,
/// so nothing ships in the bundle. A name that does not resolve falls back to
/// Hero rather than going quiet -- silence is the worst failure a notifier can
/// have, and it looks identical to "no message arrived".
///
/// `AudioPlayer` in helpers/ cannot serve here: it resolves through
/// `Bundle.main` and force-unwraps the URL.
@MainActor
enum MerMotionSound {
    private static let fallbackName = "Hero"

    /// Held for as long as it plays. An `NSSound` that goes out of scope is
    /// deallocated mid-play and the alert is silently truncated.
    private static var playing: NSSound?

    static func play(for type: AppNotification.NotificationType) {
        guard Defaults[.merMotionSoundEnabled] else { return }

        let name = soundName(for: type)
        let volume = Float(max(0, min(1, Defaults[.merMotionVolume])))

        // Loading off the main thread so a cold sound file cannot stutter the
        // notch animation that is starting at the same moment.
        DispatchQueue.global(qos: .userInitiated).async {
            let sound = load(name)
            DispatchQueue.main.async {
                guard let sound else { return }
                sound.volume = volume
                playing = sound
                sound.play()
            }
        }
    }

    private static func soundName(for type: AppNotification.NotificationType) -> String {
        switch type {
        case .directMessage: return Defaults[.merMotionSoundDirectMessage]
        case .mention: return Defaults[.merMotionSoundMention]
        case .channel: return Defaults[.merMotionSoundChannel]
        case .generic: return Defaults[.merMotionSoundDirectMessage]
        }
    }

    /// Accepts a system sound name or an absolute path to an audio file.
    private static func load(_ name: String) -> NSSound? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("/") {
            if let sound = NSSound(contentsOf: URL(fileURLWithPath: trimmed), byReference: true) {
                return sound
            }
        } else if let sound = NSSound(named: NSSound.Name(trimmed)) {
            return sound
        }

        return NSSound(named: NSSound.Name(fallbackName))
    }

    /// The system sounds macOS ships, for the settings picker.
    nonisolated static let available = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]
}
