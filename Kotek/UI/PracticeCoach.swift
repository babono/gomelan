//
//  PracticeCoach.swift
//  Kotek
//
//  The tour of the practice screen: one control lit at a time, a line about
//  what it does, Next until it runs out.
//
//  A DIFFERENT JOB from the guide panels. Those explain ideas — what a kotekan
//  is, what the grade counts — and a panel is right for that, because ideas do
//  not live anywhere on screen. This explains CONTROLS, which do, and pointing
//  at the thing itself is worth more than any amount of describing where it is.
//  So it is a spotlight rather than a page: the screen you are about to use,
//  with one piece of it lit.
//
//  Shown once before a first session and then never unasked. It is reachable
//  again from the pause overlay, which is where somebody who has forgotten
//  what a button does will actually be — mid-session, having just stopped.
//

import SwiftUI

/// The tour, in order. Raw values are only for the step counter.
enum CoachStep: Int, CaseIterable, Identifiable {
    case session
    case score
    case panelToggle
    case half
    case tempo
    case voices

    var id: Int { rawValue }

    /// Whether the bottom panel has to be up for this step to have anything to
    /// point at.
    var needsPanel: Bool { self >= .half }

    var title: String {
        switch self {
        case .session:     return "Where you are"
        case .score:       return "How it is going"
        case .panelToggle: return "The panel"
        case .half:        return "Which half"
        case .tempo:       return "Speed"
        case .voices:      return "The voices"
        }
    }

    var detail: String {
        switch self {
        case .session:
            return "The figure you are playing, and how many times it has come round. There is no total to reach — it loops until you end it from the pause button."
        case .score:
            return "Notes that landed, then your best eight cycles in a row against the record for this figure. Both only ever climb, so a bad pass costs you nothing."
        case .panelToggle:
            return "Brings up the score and the controls. Down by default, so the gangsa has the whole screen."
        case .half:
            return "Polos lands on the beat, sangsih answers between. Swap whenever you like — the gong keeps going, and each side keeps its own score."
        case .tempo:
            return "Half speed up to one and a half. It changes without stopping the music, so you can slow a figure down the moment it gets away from you."
        case .voices:
            return "Your half plays so you can copy it; mute it once the figure is in your hands. Turn the other one on and you are playing a kotekan."
        }
    }
}

extension CoachStep: Comparable {
    static func < (a: CoachStep, b: CoachStep) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Marking the targets

/// Where each step's control is, collected from wherever it happens to be laid
/// out.
///
/// Anchors rather than measured frames: a control can say "this is me" next to
/// its own definition, and the overlay resolves every one of them into its own
/// space at the end. Passing rects around by hand would mean the tour and the
/// layout each holding a private opinion about where the buttons are.
struct CoachAnchors: PreferenceKey {
    static let defaultValue: [CoachStep: Anchor<CGRect>] = [:]

    static func reduce(value: inout [CoachStep: Anchor<CGRect>],
                       nextValue: () -> [CoachStep: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Mark this view as what `step` points at.
    ///
    /// `transformAnchorPreference`, NOT `anchorPreference`. The second SETS the
    /// preference for its subtree, wiping whatever the children put there — and
    /// the targets nest: the top bar is one step, and the score cluster and the
    /// panel button inside it are two more. Marking the bar deleted both of
    /// them, so those steps came up dimming the whole screen with nothing lit,
    /// which is the one failure mode that looks like the tour is broken rather
    /// than mispointed. This one merges into what is already there.
    func coachTarget(_ step: CoachStep) -> some View {
        transformAnchorPreference(key: CoachAnchors.self, value: .bounds) { value, anchor in
            value[step] = anchor
        }
    }
}

// MARK: - The spotlight

struct PracticeCoachOverlay: View {
    let step: CoachStep
    /// The lit control, in this view's space. nil for a beat after the panel is
    /// asked to appear — the caption still stands, it simply has no hole yet.
    let target: CGRect?
    var onNext: () -> Void
    var onSkip: () -> Void

    private let padding: CGFloat = 8
    private var isLast: Bool { step == CoachStep.allCases.last }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                dim(in: geo.size)
                if let hole { ring(hole) }
                caption(in: geo.size)
            }
            //R Nothing underneath is reachable while the tour is up. Half of
            //R these controls change what the next step is pointing at.
            .contentShape(Rectangle())
            .onTapGesture { KajarTick.strike(); onNext() }
            .animation(.easeInOut(duration: 0.24), value: target)
        }
        .transition(.opacity)
    }

    private var hole: CGRect? {
        target.map { $0.insetBy(dx: -padding, dy: -padding) }
    }

    /// One path, filled even-odd: the screen with the lit control punched out of
    /// it. Cheaper and sharper than masking one shape with another.
    private func dim(in size: CGSize) -> some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: size))
            if let hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12)) }
        }
        .fill(Color.black.opacity(0.74), style: FillStyle(eoFill: true))
        .ignoresSafeArea()
    }

    private func ring(_ hole: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Theme.buttonFill, lineWidth: 2)
            .frame(width: hole.width, height: hole.height)
            .offset(x: hole.minX, y: hole.minY)
    }

    // MARK: - The caption

    private func caption(in size: CGSize) -> some View {
        let width = min(380, size.width - 48)
        let position = captionOrigin(in: size, width: width)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(.serif(22))
                    .foregroundStyle(Theme.cream)
                Spacer()
                Text("\(step.rawValue + 1)/\(CoachStep.allCases.count)")
                    .font(.sans(12, weight: .medium))
                    .foregroundStyle(Theme.cream.opacity(0.45))
            }

            Text(step.detail)
                .font(.sans(13))
                .foregroundStyle(Theme.cream.opacity(0.78))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if !isLast {
                    Button("Skip", action: onSkip)
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.cream.opacity(0.5))
                        .buttonStyle(.kajar)
                }
                Spacer()
                PillButton(title: isLast ? "Start" : "Next",
                           trailingSystemImage: "arrow.right",
                           style: .filled, compact: true, action: onNext)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .background(Theme.deep, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.cream.opacity(0.14), lineWidth: 1)
        )
        .offset(x: position.x, y: position.y)
    }

    /// Below the lit control when it is in the top half of the screen, above it
    /// when it is in the bottom — so the caption never covers the thing it is
    /// describing. Clamped to the screen either way.
    private func captionOrigin(in size: CGSize, width: CGFloat) -> CGPoint {
        let height: CGFloat = 150
        guard let hole else {
            return CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
        }
        let below = hole.maxY + 14
        let y = below + height < size.height ? below : hole.minY - 14 - height
        return CGPoint(x: (hole.midX - width / 2).clamped(to: 24, size.width - width - 24),
                       y: y.clamped(to: 24, size.height - height - 24))
    }
}
