//
//  NotificationSourceIcon.swift
//  DynamicIsland
//
//  The mark that says which app a notification came from.
//

import SwiftUI

/// The logo for a notification source, falling back to an SF Symbol.
///
/// Two cards that differ only in a word of text read as the same card. The
/// brand mark is what tells them apart before anyone starts reading, so the
/// peek and the card both draw it from here rather than each picking a glyph.
struct NotificationSourceIcon: View {
    let source: String?

    /// The side of the square the mark is drawn in. 14pt in the card header,
    /// 12pt in the compact peek.
    var size: CGFloat = 14

    /// Only for the SF Symbol fallback -- a brand mark carries its own colour,
    /// and tinting Mattermost's white mark orange because a message was a
    /// mention would be worse than no mark at all.
    var symbolTint: Color = .blue

    var body: some View {
        if let asset = NotificationSource.logoAsset(for: source) {
            Image(asset)
                .renderingMode(NotificationSource.logoIsTemplate(for: source) ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
                .frame(width: size, height: size)
        } else {
            Image(systemName: NotificationSource.iconName(for: source))
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(symbolTint)
                .frame(width: size, height: size)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        NotificationSourceIcon(source: "mattermost", size: 28)
        NotificationSourceIcon(source: "clickmassa", size: 28)
        NotificationSourceIcon(source: "slack", size: 28)
        NotificationSourceIcon(source: nil, size: 28)
    }
    .padding()
    .background(Color.black)
}
