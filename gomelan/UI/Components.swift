//
//  Components.swift
//  gomelan
//
//  Shared UI pieces for the redesign. Two surfaces — warm "paper" (cream) and
//  warm "stage" (ink) — share these components; colours are passed in so a piece
//  reads correctly on either.
//

import SwiftUI

// MARK: - Buttons

enum PillStyle { case filled, outlined, secondary }

/// The canonical pill button (GO, NEXT, CALIBRATE, START PRACTICE, RETRY …).
/// Labels are tracked and uppercased by default to match the spec.
struct PillButton: View {
    let title: String
    var systemImage: String? = nil
    var style: PillStyle = .outlined
    var tint: Color = Theme.terracotta
    var uppercase: Bool = true
    var fullWidth: Bool = false
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 8 : 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                    .textCase(uppercase ? .uppercase : nil)
                    .tracking(uppercase ? (compact ? 1.5 : 2) : 0)
            }
            .font(.sans(compact ? 13 : 15, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, compact ? 9 : 15)
            .padding(.horizontal, compact ? 18 : 30)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .overlay(
                Capsule().strokeBorder(tint, lineWidth: style == .outlined ? 1.5 : 0)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .filled: return Theme.cream
        case .outlined: return tint
        case .secondary: return Theme.charcoal
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .filled: Capsule().fill(tint)
        case .outlined: Capsule().fill(.clear)
        case .secondary: Capsule().fill(Theme.creamSunken)
        }
    }
}

/// Filled terracotta call-to-action. Kept as a distinct name because many call
/// sites use it; it is just a non-uppercased filled `PillButton` with an icon.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.terracotta
    let action: () -> Void

    var body: some View {
        PillButton(title: title, systemImage: systemImage, style: .filled,
                   tint: tint, uppercase: false, fullWidth: true, action: action)
    }
}

/// Outlined utility button. Adapts to the surface via the ambient colour scheme,
/// so it reads on both paper (light) and stage (dark) screens.
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.sans(14, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            .overlay(Capsule().strokeBorder(.primary.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Top bar

/// The consistent screen header: optional back affordance, centred tracked
/// title, optional trailing status text. `tint` is the strong text colour for
/// the surface; supporting text is derived from it.
struct TopBar: View {
    var title: String
    var backTitle: String? = nil
    var onBack: (() -> Void)? = nil
    var trailingText: String? = nil
    /// When set, a gear button is shown at the trailing edge (e.g. open Settings).
    var settingsAction: (() -> Void)? = nil
    var tint: Color = Theme.charcoal
    var accent: Color = Theme.terracotta
    /// Slimmer header with no divider — used over full-bleed camera screens.
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.sans(12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(2.5)
                    .foregroundStyle(tint.opacity(0.65))

                HStack(spacing: 14) {
                    if let onBack {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left").font(.sans(14, weight: .medium))
                                Text(backTitle ?? "Back").font(.sans(16))
                            }
                            .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if let trailingText {
                        Text(trailingText)
                            .font(.sans(13, weight: .medium))
                            .foregroundStyle(accent)
                    }
                    if let settingsAction {
                        Button(action: settingsAction) {
                            Image(systemName: "gearshape")
                                .font(.sans(18, weight: .medium))
                                .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, compact ? 10 : 24)
            .padding(.bottom, compact ? 8 : 16)

            if !compact {
                Rectangle()
                    .fill(tint.opacity(0.12))
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Labels

/// Uppercase tracked eyebrow/section label.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.terracotta
    init(_ text: String, color: Color = Theme.terracotta) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .font(.sans(12, weight: .semibold))
            .textCase(.uppercase)
            .tracking(2.5)
            .foregroundStyle(color)
    }
}

// MARK: - Stepper

/// A −/number/+ stepper. Big serif number, circular buttons — the shared control
/// for key count and cycle count.
struct CountStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var numberSize: CGFloat = 64
    var tint: Color = Theme.terracotta
    var numberColor: Color = Theme.charcoal
    var lineColor: Color = Theme.charcoal

    var body: some View {
        HStack(spacing: 22) {
            circle(system: "minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            Text("\(value)")
                .font(.serif(numberSize, weight: .regular))
                .foregroundStyle(numberColor)
                .frame(minWidth: numberSize * 1.1)
                .contentTransition(.numericText())
            circle(system: "plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .animation(.snappy(duration: 0.2), value: value)
    }

    private func circle(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.sans(24, weight: .semibold))
                .foregroundStyle(enabled ? tint : lineColor.opacity(0.3))
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(enabled ? tint.opacity(0.08) : Color.clear)
                )
                .overlay(
                    Circle()
                        .strokeBorder(enabled ? tint.opacity(0.75) : lineColor.opacity(0.2), lineWidth: 2)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Stat bar

/// Horizontal progress bar used on the results screen ("where it slipped").
struct StatBar: View {
    var fraction: Double
    var color: Color
    var track: Color = Theme.creamSunken

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color)
                    .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 7)
    }
}

// MARK: - Busy

/// The scrim shown while something is genuinely being done — a profile written,
/// the lens settling on a lock, a baseline being folded into a template. Blocks
/// interaction, because every one of these steps ends in a screen change and a
/// second tap during the wait lands somewhere the player didn't aim.
///
/// Only ever shown around real work. A spinner that appears and vanishes in the
/// same frame reads as a glitch, not as progress.
struct BusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            //R A dark card on a dark camera feed disappeared into it — three
            //R shades of near-black stacked on each other. Solid cream, so it
            //R reads as a lit panel over the stage whatever is behind it,
            //R including an unlit room.
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.terracotta)
                    .scaleEffect(1.3)
                Text(message)
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.charcoal)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
            .frame(minWidth: 260)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Theme.terracotta.opacity(0.5), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        }
    }
}

extension View {
    /// Covers this view with `BusyOverlay` while `message` is non-nil.
    ///
    /// No cross-fade: these waits are often under a second, and a fade meant the
    /// scrim spent a good part of its life half-transparent — which is exactly
    /// when it looks like a faint smudge rather than a loading state.
    func busy(_ message: String?) -> some View {
        overlay {
            if let message { BusyOverlay(message: message) }
        }
    }
}

// MARK: - Realign affordance

/// A persistent "keys misaligned?" affordance (PRD §13.4).
struct RealignButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Realign", systemImage: "viewfinder")
                .font(.sans(13, weight: .medium))
                .foregroundStyle(Theme.terracotta)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .overlay(Capsule().strokeBorder(Theme.terracotta.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
