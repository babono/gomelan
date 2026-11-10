//
//  AddSharedKotekanPhase.swift
//  Kotek
//
//  Where the add screen is with the figure behind the link. It was a name
//  that was nil while loading, "" when the link led nowhere, and an error
//  string beside it — three fields for one question.
//

import Foundation

enum AddSharedKotekanPhase: Equatable {
    case loading
    case ready(Kotekan)
    /// The link leads nowhere: deleted, or never a player's figure.
    case notFound
    /// Unknown, not gone: the link can be opened again.
    case failed
}
