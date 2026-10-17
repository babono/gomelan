//
//  ControlProminence.swift
//  Kotek
//
//  How loudly a control speaks. The one thing a call site chooses about a
//  button's look — everything else (surface, type, size, padding) belongs to
//  the component, so two screens cannot drift apart.
//

import SwiftUI

enum ControlProminence: Equatable {
    /// The screen's one main action: gold glass, brand-voice type.
    case primary
    /// Everything else: flat glass, the card brown.
    case standard
    /// The chosen one of a few: solid gold with dark type. Gold only — a
    /// selection that took each choice's own colour (blue polos, purple
    /// sangsih) was far too loud next to the one main action.
    case selected
    /// Delete, sign out, forget: red, and announced as destructive.
    case destructive
    /// A state carried by colour — a selected chip, a recording button. Red is
    /// not the same as destructive: stopping a recording destroys nothing.
    case tinted(Color)

    /// What `Button` should be told, so VoiceOver and the system agree.
    var role: ButtonRole? {
        self == .destructive ? .destructive : nil
    }
}
