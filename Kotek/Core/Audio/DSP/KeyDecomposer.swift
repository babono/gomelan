//
//  KeyDecomposer.swift
//  Kotek
//
//  Which keys are sounding right now, and how strongly — the polyphonic
//  counterpart to KeyClassifier's single-winner cosine match.
//
//  Gomelan identifies keys by SIGHT: the camera knows where each bilah is, so
//  it answers "which key" by location and never has to tell two pitches apart.
//  Sound answers "when", and whether a strike was real. That split is why the
//  per-key audio templates went unused.
//
//  This brings sound back as a SECOND OPINION, in the one place vision has
//  nothing to say. When a mallet is occluded, or the player's hand covers the
//  bar at the moment of impact, `resolveVisionFirst` returns nil and the strike
//  is dropped — a real hit, scored as a miss. The ear was not occluded. If the
//  dictionary can name the key, the strike is recovered.
//
//  It never overrides vision. Where vision is confident, vision wins; disagreement
//  is recorded, not acted on. Audio-by-pitch is the weaker signal in a gamelan —
//  the pengisep two metres away is playing the same figure a few Hz sharp — and
//  it earns a vote only by first agreeing with the eye for a while.
//
//  Self-calibrating, on purpose. There is no "strike each key in turn" step and
//  there should not be: it was tried, it is tedious, and one template per key
//  captures only whichever dynamic was used that day. Instead every strike vision
//  is CONFIDENT about donates its spectrum to that key's atom. The dictionary
//  builds itself, on this instrument, in this room, at this mic distance, across
//  the dynamics actually being played — and it keeps improving for as long as
//  the app is used.
//

import Accelerate

/// One key's learned spectrum, and how many strikes went into it.
///
/// The count is half the atom. Without it, partial progress cannot be written
/// down, and a dictionary that can only be saved once it is finished is a
/// dictionary that mostly never gets saved.
nonisolated struct LearnedAtom: Equatable {
    var bands: [Float]
    var examples: Int
}

struct KeyActivation {
    let keyIndex: Int
    /// Raw activation, in the observation's units — carries loudness.
    let activation: Float
    /// This key's share of the energy explained by KEY atoms (noise excluded).
    let share: Float
}

struct Decomposition {
    let activations: [KeyActivation]
    /// Energy no atom could explain, 0...1. High = something not in the
    /// dictionary. See `NNLSDictionary.residualFraction`.
    let residual: Float
    /// Share of the fit taken by the broadband noise atom, 0...1.
    let noiseShare: Float
    /// Activations before the ring subtraction, atom-ordered rather than
    /// key-ordered. Diagnostic only — the decomposer keeps its own copy for the
    /// next strike.
    let raw: [Float]
    /// Whether `residual` is close enough to what this instrument normally
    /// produces for the ranking to be worth acting on. False while the bar is
    /// still being learned — silence is the safe answer for a recovery path.
    let isTrusted: Bool

    /// The most likely newly struck key, or nil when nothing is clear enough.
    var best: KeyActivation? { activations.first }
}

final class KeyDecomposer {

    /// Strikes vision must confidently attribute to a key before that key's atom
    /// is trusted for recovery. One example is a single dynamic and possibly a
    /// mis-seen one; by four the template has averaged across the hard and soft
    /// hits that actually occur in a figure.
    static let strikesToTrustAtom = 4

    /// A key's share must clear this to be reported at all. Below it the energy
    /// is more likely decay tail than a fresh attack.
    var shareFloor: Float = 0.18

    /// How far above the typical residual a fit may sit and still be believed.
    ///
    /// There is no absolute number here on purpose. Residual depends on how
    /// dense the band vector is, which depends on the room, the mic distance and
    /// how much broadband click the mallet makes — quantities that differ between
    /// a bedroom and a banjar. A synthetic check produced 0.008 for an exact
    /// match and 0.687 for one whose partials had moved eight cents, which is a
    /// spread wide enough to prove only that a fixed constant would be a guess.
    ///
    /// So the bar is measured instead, from strikes the CAMERA confirmed: those
    /// are known-real, known-correct hits on this instrument, and whatever
    /// residual they produce is what "normal" means here. Same adaptive-median
    /// shape as the onset threshold in `OnsetDetector`.
    private static let residualMultiplier: Float = 1.7
    /// Residual samples needed before the bar means anything.
    private static let residualSamplesNeeded = 8
    /// Refresh an already-trusted atom every this many further examples.
    private static let rebuildStride = 4
    /// Examples taken on trust before quarantine starts judging.
    private static let quarantineSeedCount = 2
    /// Cosine an example must reach against the existing atom to be folded in.
    /// Deliberately loose — hard and soft strikes on one bar genuinely differ,
    /// and this is meant to catch a wrong BAR, not a different dynamic.
    private static let learnConsistency: Float = 0.55

    private let bandCount: Int
    /// Running sum of harvested linear vectors per key index, and how many went
    /// into it. Averaging in sum-space and normalising on read means a late
    /// strike costs one vector-add, not a rebuild.
    private var learned: [Int: (sum: [Float], count: Int)] = [:]
    /// Bilah the current figure uses. Empty = every learned key.
    private var activeKeys: Set<Int> = []
    /// Residuals from strikes the camera confirmed — the sample the trust bar
    /// is drawn from.
    private var confirmedResiduals: [Float] = []
    /// Last strike's activations, for the decay subtraction. Atom-ordered, so it
    /// is only valid for the dictionary that produced it.
    private var previousActivations: [Float]?

    /// Rebuilt whenever the trusted key set changes, never per strike.
    private var dictionary: NNLSDictionary?
    /// Which key each atom row belongs to; the final row is the noise atom.
    private var atomKeys: [Int] = []

    init(bandCount: Int) {
        self.bandCount = bandCount
    }

    // MARK: - Dictionary

    /// Key indices whose atom has enough examples AND are in play. Empty
    /// `activeKeys` means no restriction.
    var trustedKeys: [Int] {
        learned
            .filter { $0.value.count >= Self.strikesToTrustAtom }
            .keys
            .filter { activeKeys.isEmpty || activeKeys.contains($0) }
            .sorted()
    }

    /// Narrow the dictionary to the bilah the current figure uses. Learning is
    /// unaffected — a key outside the figure still accumulates examples, ready
    /// for the kotekan that does use it.
    func restrict(to indices: Set<Int>) {
        guard indices != activeKeys else { return }
        activeKeys = indices
        rebuild()
    }

    /// Examples collected per key, for the diagnostics screen.
    func progress() -> [Int: Int] { learned.mapValues(\.count) }

    /// How often eye and ear reached the same answer.
    ///
    /// Recorded even though audio never overrides vision, because this is the
    /// only evidence that could ever justify letting it. Two very different
    /// events look identical from the scorer's side — vision mislocalising at an
    /// octave boundary, and a student genuinely striking the wrong bilah — and
    /// only the ear can tell them apart. Acting on that now would be guessing;
    /// counting it is how the guess gets replaced with a measurement.
    struct Agreement {
        var agreed = 0
        var disagreed = 0
        /// Vision decided, audio had no trustworthy opinion to offer.
        var noOpinion = 0
        /// Vision could not localise; audio supplied the key.
        var recovered = 0
        /// Examples rejected by the quarantine check.
        var quarantined = 0
        /// The last few disagreements, newest last, for the diagnostics screen.
        var recent: [Disagreement] = []

        var agreementRate: Double {
            let total = agreed + disagreed
            return total > 0 ? Double(agreed) / Double(total) : 0
        }
    }

    struct Disagreement {
        let visionKey: Int
        let visionConfidence: Double
        let heardKey: Int
        let heardShare: Float
        let residual: Float
    }

    private(set) var agreement = Agreement()
    private var quarantined = 0 { didSet { agreement.quarantined = quarantined } }

    /// Compare the camera's answer with the ear's, and tally.
    func noteVisionDecision(keyIndex: Int, confidence: Double, against decomposition: Decomposition?) {
        guard let decomposition, decomposition.isTrusted, let heard = decomposition.best else {
            agreement.noOpinion += 1
            return
        }
        if heard.keyIndex == keyIndex {
            agreement.agreed += 1
        } else {
            agreement.disagreed += 1
            agreement.recent.append(Disagreement(visionKey: keyIndex,
                                                 visionConfidence: confidence,
                                                 heardKey: heard.keyIndex,
                                                 heardShare: heard.share,
                                                 residual: decomposition.residual))
            if agreement.recent.count > 20 { agreement.recent.removeFirst() }
        }
    }

    func noteRecovery() { agreement.recovered += 1 }

    var isUsable: Bool { (dictionary?.atomCount ?? 0) > 1 }

    /// Fold one strike's linear band vector into a key's atom.
    ///
    /// Vectors are L2-normalised BEFORE summing, so a hard strike does not drown
    /// four soft ones — the atom is a shape, averaged over dynamics, and the
    /// loudness lives in the activation instead.
    /// Returns whether the example was folded in, or quarantined as an outlier.
    @discardableResult
    func learn(keyIndex: Int, linearBands: [Float]) -> Bool {
        guard linearBands.count == bandCount,
              let unit = Self.l2Normalised(linearBands) else { return false }

        // Quarantine. Vision's label is a good label, not a perfect one, and an
        // atom is a permanent thing: one confident mislabel merges a wrong
        // spectrum into a template that then goes on to attract more of the
        // same, and the corruption persists across sessions because the atom is
        // saved to the profile. So an example must look like what this key has
        // already sounded like to be accepted.
        //
        // Same shape as `baselineLearnConsistency` in AudioEngineController,
        // including the seed allowance: the first examples have nothing to be
        // compared against and are taken on trust.
        let previous = learned[keyIndex]?.count ?? 0
        if previous >= Self.quarantineSeedCount,
           let entry = learned[keyIndex],
           let atom = Self.l2Normalised(entry.sum) {
            var similarity: Float = 0
            vDSP_dotpr(atom, 1, unit, 1, &similarity, vDSP_Length(bandCount))
            guard similarity >= Self.learnConsistency else {
                quarantined += 1
                return false
            }
        }

        if var entry = learned[keyIndex] {
            let n = vDSP_Length(bandCount)
            entry.sum.withUnsafeMutableBufferPointer { dst in
                vDSP_vadd(dst.baseAddress!, 1, unit, 1, dst.baseAddress!, 1, n)
            }
            entry.count += 1
            learned[keyIndex] = entry
        } else {
            learned[keyIndex] = (sum: unit, count: 1)
        }

        // Crossing the threshold changes the trusted SET and must rebuild. Every
        // strike after that only refines an atom already present, which is worth
        // picking up but not worth an O(atoms² x bands) Gram rebuild each time —
        // so it happens on a stride instead.
        let count = previous + 1
        if count == Self.strikesToTrustAtom
            || (count > Self.strikesToTrustAtom && count % Self.rebuildStride == 0) {
            rebuild()
        }
        return true
    }

    /// Discard everything learned — a new instrument, or a moved microphone.
    func reset() {
        learned.removeAll()
        dictionary = nil
        atomKeys = []
        previousActivations = nil
        confirmedResiduals.removeAll()
    }

    /// Seed from templates persisted with the profile.
    func load(atoms: [Int: LearnedAtom]) {
        learned.removeAll()
        for (index, atom) in atoms where atom.bands.count == bandCount {
            if let unit = Self.l2Normalised(atom.bands) {
                learned[index] = (sum: unit, count: max(1, atom.examples))
            }
        }
        rebuild()
    }

    /// Everything learned so far, for persisting back into the profile.
    ///
    /// EVERY key, including the ones that have not reached
    /// `strikesToTrustAtom` yet — which is the whole point. This used to filter
    /// on the trust threshold, so a session that collected one, two or three
    /// examples of a bilah saved nothing for it and the next session started
    /// that key from zero. Four examples in one sitting is not a given; four
    /// across four sittings ought to be, and was not.
    ///
    /// The count travels with the vector, so trust is a property of the atom
    /// rather than of the session that happened to be running. `trustedKeys`
    /// still refuses to DECOMPOSE with anything under four, so nothing this
    /// changes reaches a judgement — it only stops the counter being reset.
    func snapshot() -> [Int: LearnedAtom] {
        var out: [Int: LearnedAtom] = [:]
        for (index, entry) in learned {
            if let unit = Self.l2Normalised(entry.sum) {
                out[index] = LearnedAtom(bands: unit, examples: entry.count)
            }
        }
        return out
    }

    private func rebuild() {
        // Atom order is about to change; anything measured against the old order
        // is meaningless now.
        previousActivations = nil
        let keys = trustedKeys
        guard keys.count >= 2 else { dictionary = nil; atomKeys = []; return }

        var atoms: [[Float]] = []
        atoms.reserveCapacity(keys.count + 1)
        for key in keys {
            guard let entry = learned[key], let unit = Self.l2Normalised(entry.sum) else { continue }
            atoms.append(unit)
        }
        guard atoms.count == keys.count else { return }

        // The noise atom. A flat vector across LOG-spaced bands is a rising
        // spectrum in linear frequency, which is roughly what a room floor plus
        // a mallet click looks like through these bands. Its job is not accuracy
        // — it is to give broadband energy somewhere to go other than into a
        // key, which is what makes activation share mean anything in a noisy hall.
        if let noise = Self.l2Normalised([Float](repeating: 1, count: bandCount)) {
            atoms.append(noise)
        }

        atomKeys = keys + [-1]
        dictionary = NNLSDictionary(normalisedAtoms: atoms)
    }

    // MARK: - Decomposition

    /// Decompose one strike's linear band vector.
    ///
    /// The previous strike's activations are held internally and subtracted from
    /// this one. Bronze only decays, so a key already ringing cannot have grown:
    /// taking away most of its previous level leaves only genuinely new energy,
    /// and stops a loud sustaining key from masking the quieter one that was
    /// actually just struck. The subtraction happens in ACTIVATION space, not on
    /// the spectrum — clipping a spectrum at zero where two keys' partials
    /// collide mangles the shape of the new note, which is the one thing that
    /// must survive intact.
    ///
    /// Held here rather than passed in by the caller because only this type knows
    /// when the dictionary was rebuilt. Activation vectors are ATOM-ordered, so
    /// after a rebuild the same array length can mean an entirely different set
    /// of keys, and subtracting one from the other would quietly suppress the
    /// wrong bilah. `rebuild()` drops it; the caller cannot forget to.
    func decompose(linearBands y: [Float]) -> Decomposition? {
        guard let dictionary, y.count == bandCount else { return nil }
        let previous = previousActivations

        let raw = dictionary.solve(observation: y)
        let residual = dictionary.residualFraction(observation: y, activations: raw)
        previousActivations = raw
        var x = raw

        if let previous, previous.count == x.count {
            for i in x.indices where atomKeys[i] >= 0 {
                x[i] = max(0, x[i] - previous[i] * Self.decayAllowance)
            }
        }

        var keyTotal: Float = 0
        var noise: Float = 0
        for (i, value) in x.enumerated() {
            if atomKeys[i] >= 0 { keyTotal += value } else { noise += value }
        }
        guard keyTotal > 1e-9 else { return nil }

        let activations = x.enumerated().compactMap { i, value -> KeyActivation? in
            let key = atomKeys[i]
            guard key >= 0 else { return nil }
            let share = value / keyTotal
            guard share >= shareFloor else { return nil }
            return KeyActivation(keyIndex: key, activation: value, share: share)
        }
        .sorted { $0.activation > $1.activation }

        return Decomposition(activations: activations,
                             residual: residual,
                             noiseShare: noise / (keyTotal + noise),
                             raw: raw,
                             isTrusted: residualBar.map { residual <= $0 } ?? false)
    }

    /// The learned residual bar, or nil while too few confirmed strikes have
    /// been seen for a median to mean anything.
    private var residualBar: Float? {
        guard confirmedResiduals.count >= Self.residualSamplesNeeded else { return nil }
        let sorted = confirmedResiduals.sorted()
        let median = sorted[sorted.count / 2]
        return median * Self.residualMultiplier
    }

    /// Record what a KNOWN-good strike's residual looked like. Only ever fed
    /// from vision-confirmed hits — feeding it unverified strikes would let the
    /// bar drift up to accommodate exactly the sounds it exists to exclude.
    func noteConfirmedResidual(_ value: Float) {
        confirmedResiduals.append(value)
        if confirmedResiduals.count > 60 { confirmedResiduals.removeFirst() }
    }

    /// How much of a ringing key's previous activation to hold back. Not 1.0:
    /// the fit is noisy, and subtracting the full previous level turns ordinary
    /// estimation error into a suppressed re-strike of the same key — which in
    /// kotekan, where a key is frequently struck twice in a row, is the exact
    /// note you cannot afford to lose. Lower it toward 0.7 if soft strikes go
    /// missing after a loud one.
    private static let decayAllowance: Float = 0.85

    private static func l2Normalised(_ vector: [Float]) -> [Float]? {
        var out = vector
        let n = vDSP_Length(out.count)
        var norm: Float = 0
        vDSP_svesq(out, 1, &norm, n)
        norm = sqrt(norm)
        guard norm > 1e-9 else { return nil }
        var inverse = 1 / norm
        out.withUnsafeMutableBufferPointer { dst in
            vDSP_vsmul(dst.baseAddress!, 1, &inverse, dst.baseAddress!, 1, n)
        }
        return out
    }
}
