//
//  SharePreview.swift
//  Kotek
//
//  Debug: the add-shared-kotekan screen in each of its states, opened from
//  Settings › Debug without a link, a second account or a deleted figure.
//  The screen is the real one; only where its data comes from changes —
//  a bundled figure instead of `shared_kotekan_figure` — and nothing it does
//  reaches the server: Add closes, Sign in with Apple links nothing.
//

#if DEBUG
    enum SharePreview: CaseIterable {
        /// A figure, and the player's own gangsa to choose from.
        case regular
        /// A figure, and no gangsa yet.
        case noGangsa
        /// The link leads nowhere.
        case brokenLink
        /// A guest, asked to link an Apple ID first.
        case signIn
    }
#endif
