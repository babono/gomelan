//
//  ReviewKotekView.swift
//  Kotek
//
//  The whole figure before it is saved: both halves and the colotomic lane on
//  one piano roll, fitted to the screen, and played together — the editor
//  dims the half not being written, so this is the one place to see and hear
//  the weave as a whole.
//
//  It used to be a table: a row per half, a column per slot numbered 1…G, the
//  bilah's number in each cell, every cell a menu. That was the wrong shape
//  twice over — a figure written in 1/32s or triplets came out as dozens of
//  columns, and reading a melody as a row of numbers is harder than seeing it
//  climb and fall. Changes are made back in the editor (Edit), where the same
//  picture is.
//
//  The name is asked for in a popup on Save: it is the last thing a player
//  knows, not the first, and a field on the screen sat between them and the
//  figure they came here to hear.
//

import SwiftUI

struct ReviewKotekView: View {
    let viewModel: CreateKotekViewModel
    @State private var naming = false

    var body: some View {
        @Bindable var draft = viewModel.draft

        VStack(spacing: 10) {
            CreateTopBar(
                title: String(localized: "Review"),
                subtitle: "\(draft.bpm) BPM · \(String(localized: "\(draft.bars) bars")) · \(draft.source == .automatic ? String(localized: "Recorded") : String(localized: "Tapped in"))"
            ) {
                AppIconButton(systemImage: "chevron.left", label: "Back") { viewModel.back() }
            } trailing: {
                EmptyView()
            }

            HStack {
                Spacer()
                ReviewLegend()
            }

            PatternOverview(viewModel: viewModel)

            HStack(spacing: 12) {
                AppIconButton(systemImage: "stop.fill", label: "Back to start") {
                    viewModel.stopPreview()
                }
                AppIconButton(
                    systemImage: viewModel.playing ? "pause.fill" : "play.fill",
                    label: viewModel.playing ? "Pause" : "Play",
                    prominence: .primary
                ) { viewModel.togglePlay() }
                PlayheadClock(viewModel: viewModel)
                    .padding(.leading, 4)

                Spacer(minLength: 12)

                if let error = viewModel.saveError {
                    Text(error)
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(Theme.miss)
                        .lineLimit(2)
                }
                AppButton(title: "Edit") { viewModel.back() }
                AppButton(title: viewModel.saving ? "Saving…" : "Save", prominence: .primary) {
                    viewModel.pause()
                    naming = true
                }
                .disabled(!viewModel.canSave)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 10)
        // The system alert with a text field was tried first. In landscape
        // the keyboard turns it into a full-screen entry sheet with its button
        // drawn on its side, so this is a card of our own, pinned near the top
        // where the keyboard does not reach.
        .overlay {
            if naming {
                NamePopup(name: $draft.name, onCancel: { naming = false }) {
                    naming = false
                    viewModel.save()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: naming)
        .ignoresSafeArea(.keyboard)
    }
}

/// Asks for the name, then saves.
private struct NamePopup: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 12) {
                Text("Name your kotek")
                    .font(.serif(24))
                    .foregroundStyle(Theme.cream)
                TextField("My kotekan", text: $name)
                    .textFieldStyle(.plain)
                    .font(.sans(17))
                    .foregroundStyle(Theme.cream)
                    .focused($focused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit(onSave)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Theme.deep, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.buttonFill, lineWidth: 2))
                HStack(spacing: 12) {
                    AppButton(title: "Cancel", fullWidth: true, action: onCancel)
                    AppButton(title: "Save", prominence: .primary, fullWidth: true, action: onSave)
                }
            }
            .padding(20)
            .frame(width: 420)
            .background(Theme.ground, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
            .padding(.top, 12)
        }
        .onAppear { focused = true }
    }
}

/// The figure fitted to the width: no scrolling, no zoom — the point is to see
/// all of it at once.
private struct PatternOverview: View {
    let viewModel: CreateKotekViewModel

    private let labelWidth: CGFloat = 28
    private let rulerHeight: CGFloat = 22
    private let laneHeight: CGFloat = 28
    /// Room either side, so a gong on the first or last line shows its ring.
    private let lead: CGFloat = 12

    var body: some View {
        let draft = viewModel.draft
        let notes = draft.notes
        let colotomic = draft.colotomic
        let length = draft.lengthTicks
        let bars = draft.bars
        let rows = viewModel.keyCount

        GeometryReader { geo in
            let visible = max(1, geo.size.width - labelWidth - lead * 2)
            let pxPerTick = visible / CGFloat(length)
            let rowHeight = max(10, (geo.size.height - rulerHeight - laneHeight) / CGFloat(rows))

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach((0 ..< rows).reversed(), id: \.self) { key in
                        Text("\(key + 1)")
                            .font(.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.stone)
                            .frame(height: rowHeight)
                    }
                    Image(systemName: "circle.circle")
                        .font(.symbol(11, weight: .semibold))
                        .foregroundStyle(Theme.stone)
                        .frame(height: laneHeight)
                        .accessibilityLabel("Gong, kempur, klentong and kajar")
                }
                .padding(.top, rulerHeight)
                .frame(width: labelWidth)

                VStack(spacing: 0) {
                    PianoRollRuler(bars: bars, pxPerTick: pxPerTick)
                        .frame(height: rulerHeight)
                        .padding(.leading, lead)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            viewModel.seek(toTick: Int((location.x - lead) / pxPerTick))
                        }
                    PianoRollCanvas(
                        notes: notes,
                        colotomic: colotomic,
                        lengthTicks: length,
                        patternTicks: length,
                        snapTicks: Subdivision.quarter.ticks,
                        writing: nil,
                        rows: rows,
                        laneHeight: laneHeight,
                        lead: lead,
                        pxPerTick: pxPerTick
                    )
                    .frame(height: rowHeight * CGFloat(rows) + laneHeight)
                }
                .overlay(alignment: .topLeading) {
                    PreviewPlayhead(viewModel: viewModel, pxPerTick: pxPerTick)
                        .padding(.leading, lead)
                }
                .clipped()
            }
        }
        .background(Theme.deep.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.radius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

/// What each colour is, since nothing here is labelled by half any more.
private struct ReviewLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            voice(.polos, Theme.polosVoice)
            voice(.sangsih, Theme.sangsihVoice)
            ForEach(ColotomicInstrument.allCases) { instrument in
                HStack(spacing: 5) {
                    ColotomicMark(instrument: instrument, scale: 0.65)
                    Text(instrument.title)
                }
            }
        }
        .font(.sans(13))
        .foregroundStyle(Theme.stone)
        .fixedSize()
    }

    private func voice(_ half: KotekanHalf, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 7)
            Text(half.title)
        }
    }
}
