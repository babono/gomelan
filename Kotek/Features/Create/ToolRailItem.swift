//
//  ToolRailItem.swift
//  Kotek
//
//  One icon of the tool rail.
//

import SwiftUI

/// Only draws: the rail owns the touch, because a hold on the rail slides from
/// one icon to the next and no single icon sees that. What it does carry is the
/// accessibility side, so VoiceOver gets a real button with a real name
/// whatever the touch handling is.
struct ToolRailItem<Mark: View>: View {
    /// What VoiceOver hears — it always gets the name, whatever is on screen.
    let accessibilityName: String
    let selected: Bool
    let thumb: Namespace.ID
    let onActivate: () -> Void
    @ViewBuilder let mark: () -> Mark

    var body: some View {
        mark()
            .frame(width: 36, height: 36)
            .background {
                if selected {
                    // The same sliding thumb as the play screens' toggle — and
                    // not gold, which the gong's own ring would vanish into.
                    AppThumb(shape: Circle())
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
            // 36 tall, not 44: the rail has to fit the grid's height on the
            // smallest phone, where the home-indicator inset leaves ~197pt.
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onActivate)
    }
}
