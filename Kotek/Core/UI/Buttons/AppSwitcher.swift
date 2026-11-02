//
//  AppSwitcher.swift
//  Kotek
//
//  A two-way choice: Polos / Sangsih.
//

import SwiftUI

/// Two looks for the same choice, picked by the screen:
/// - `.toggle`, the play screens': the HIG's segmented toggle ("All | Missed"),
///   one Krem track with a white thumb that slides under the chosen label.
/// - `.pills`, the Create screen's: chips — the chosen one Ireng, the rest
///   white and outlined, as the design system's "All" filter.
///
/// In both, selection never changes the type — the same face, size and weight
/// whichever is chosen. The primary's heavy uppercase on the chosen segment made
/// the label jump in weight, case and width on every tap.
struct AppSwitcher<Option: Hashable>: View {
    enum Style { case toggle, pills }

    let options: [Option]
    /// nil leaves nothing chosen, for when the row is showing something else
    /// (the piano roll writing a colotomic instrument).
    let selection: Option?
    let title: (Option) -> String
    /// A coloured dot before the label, e.g. the voice's colour.
    var dot: (Option) -> Color? = { _ in nil }
    /// `.toggle` only: the thumb in this colour, its label white, instead of
    /// white with the label in ink — Polos red and Sangsih blue, so the
    /// switch shows the colour of the notes it will drop.
    var tint: (Option) -> Color? = { _ in nil }
    var size = AppButtonSize.compact
    var style = Style.toggle
    let onSelect: (Option) -> Void

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The thumb's inset from the track.
    private let inset: CGFloat = 3

    var body: some View {
        switch style {
        case .toggle: toggle
        case .pills: pills
        }
    }

    private func label(_ option: Option) -> some View {
        HStack(spacing: 6) {
            if let color = dot(option) {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(title(option)).appLabel(size)
        }
    }

    private var toggle: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                let tinted = tint(option)
                Button {
                    onSelect(option)
                } label: {
                    label(option)
                        // Colour only: the type itself never changes with selection.
                        .foregroundStyle(
                            selected && tinted != nil ? Theme.onButtonFill : Theme.cream.opacity(selected ? 1 : 0.65)
                        )
                        .padding(.horizontal, size.horizontalPadding - inset)
                        .frame(height: size.height)
                        .background {
                            if selected {
                                AppThumb(shape: Capsule(), fill: tinted ?? Theme.surface)
                                    .padding(inset)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.appPlain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background(Theme.deep, in: Capsule())
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selection)
        // Never squeezed: a row too wide for its screen used to slide the
        // second segment over the first.
        .fixedSize()
        .layoutPriority(1)
        .accessibilityElement(children: .contain)
    }

    private var pills: some View {
        Group {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let selected = selection == option
                    Button {
                        onSelect(option)
                    } label: {
                        label(option)
                            .foregroundStyle(selected ? Theme.onGlassFill : Theme.cream)
                            .appControlSurface(
                                size: size,
                                shape: .capsule,
                                prominence: selected ? .selected : .secondary
                            )
                    }
                    .buttonStyle(.appPlain)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .fixedSize()
        }
        .layoutPriority(1)
    }
}
