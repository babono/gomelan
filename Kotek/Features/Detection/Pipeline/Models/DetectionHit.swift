//
//  DetectionHit.swift
//  Kotek
//
//  A single detected strike in the detection test diagnostic pipeline.
//

import Foundation

struct DetectionHit: Identifiable, Equatable {
    let id: UUID
    let key: Int
    let prob: Double
    let audioSnapped: Bool
    /// What the ear made of the same strike — nil when the dictionary had
    /// nothing to say (too few atoms yet, or no onset to decompose).
    var heardKey: Int?
    var heardShare: Float?
    var residual: Float?
    var heardTrusted: Bool

    init(
        id: UUID = UUID(),
        key: Int,
        prob: Double,
        audioSnapped: Bool,
        heardKey: Int? = nil,
        heardShare: Float? = nil,
        residual: Float? = nil,
        heardTrusted: Bool = false
    ) {
        self.id = id
        self.key = key
        self.prob = prob
        self.audioSnapped = audioSnapped
        self.heardKey = heardKey
        self.heardShare = heardShare
        self.residual = residual
        self.heardTrusted = heardTrusted
    }

    var agrees: Bool? {
        heardKey.map { $0 == key }
    }
}
