//
//  PianoRollView.swift
//  Kotek
//
//  The Create Kotek editor: a piano roll with bilah for rows, modelled on a
//  DAW's editor (Signal, CapCut's timeline). Tap to write a stroke, tap it
//  again to take it out. The grid scrolls both ways and pinches to zoom; the
//  snap value sets the width of a new stroke and where it lands, and the grip
//  on a stroke's end drags it longer or shorter from there.
//
//  Laid out like GarageBand: the gangsa is out at the bottom to play on, and
//  the roll above it is a small overview. A tap on the overview puts the
//  gangsa away and opens the roll to edit.
//
//  Record runs the line as playback does, and a hit — from a sensor or the
//  drawn gangsa — is written in the snap step the line is in for the half
//  being written. The line has a flag on the ruler, as in GarageBand: drag along
//  the numbers to move it.
//
//  Under the rows runs a colotomic lane: the gong cycle the draft lays under
//  the figure (`KotekanDraft.colotomic`), drawn as circles on the line each
//  sounds on, the way a gamelan score video marks them.
//
//  Rows are key INDICES from the active instrument, top row highest — never
//  pitches, same as everywhere else (PRD §7).
//

import SwiftUI

struct PianoRollView: View {
    @Bindable var viewModel: CreateKotekViewModel

    var body: some View {
        let draft = viewModel.draft

        VStack(spacing: 6) {
            // The transport where the title was: the bottom of the screen is
            // the gangsa's, and "New Kotek" said nothing the screen didn't.
            ZStack {
                PianoRollTransport(viewModel: viewModel)
                HStack(spacing: 12) {
                    AppIconButton(systemImage: "chevron.left", label: "Back") { viewModel.back() }
                    Spacer()
                    RecordControl(viewModel: viewModel)
                    AppButton(title: "Next", prominence: .primary) { viewModel.review() }
                        .disabled(draft.isEmpty)
                }
            }
            .frame(minHeight: 50)

            // Tight: on a phone the row only just holds every control (see
            // `PianoRollControls`).
            HStack(spacing: 6) {
                PianoRollControls(viewModel: viewModel)
                // The figure's own tempo, saved with it. A Tempo menu sat
                // beside it for the preview's speed: two controls for one thing.
                BPMField(bpm: Bindable(draft).bpm)
                // The gong cycle under the figure. Its own control, not a
                // tool: the colotomic line is laid, never drawn by hand.
                AppMenuPicker(
                    options: ColotomicTemplate.allCases,
                    selection: Bindable(draft).template,
                    title: \.title,
                    label: "Gong cycle",
                    systemImage: "circle.circle"
                )
                // Under Next, where it sat before the transport took it.
                AppMenuPicker(
                    options: Subdivision.denominators.map(Subdivision.init(denominator:)),
                    selection: $viewModel.snap,
                    title: \.label,
                    label: "Snap",
                    systemImage: "squareshape.split.3x3"
                )
            }

            if viewModel.showsGangsa {
                PianoRollGrid(viewModel: viewModel, compact: true)
                // Inside the safe area, unlike the play screen's: there the
                // gangsa is only watched, here it is played, and bars sunk to
                // the glass sat under the home indicator, where a tap went
                // to the system's swipe instead of the bilah.
                HStack(spacing: 8) {
                    TouchGangsa(viewModel: viewModel)
                    // Beside the bars, where the fingers are: step entry's
                    // rest, the same move as the transport's skip.
                    AppButton(title: "Gap") { viewModel.skip() }
                        .disabled(viewModel.recording)
                }
                .padding(.bottom, 4)
                // A swipe off a bar must not go home on the first try.
                .defersSystemGestures(on: .bottom)
            } else {
                PianoRollGrid(viewModel: viewModel, compact: false)
                    .padding(.bottom, 4)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showsGangsa)
        // The count before a take, as the play screen counts back in from a
        // pause. Not in the way of a finger: a hit on the four still counts.
        .overlay {
            if let n = viewModel.countIn {
                Text("\(n)")
                    .font(.serif(96))
                    .foregroundStyle(Theme.cream)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .id(n)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: viewModel.countIn)
        // On top of the safe area, not instead of it: the landscape inset
        // already clears the notch and home indicator. Tight both ways: the
        // tools row needs the width, and fourteen bilah rows need the height.
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}

// MARK: - Controls row

/// The halves, the eraser, then the gangsa. Zoom is a pinch; it had buttons
/// too, and they were two more glyphs for something the fingers already do. The colotomic
/// instruments used to be tools here; the draft lays them now. A row too wide
/// for a small phone scrolls rather than squeezing one chip over the next.
///
/// The gangsa button stays out of the scroll. Inside it, it was the last
/// thing in the row and the first to go: once the BPM field came back, a
/// phone's row had no room left for it, and the gangsa could not be got out
/// without knowing to swipe the tools. The thin dividers between the halves,
/// the eraser and the gangsa went for the same room.
///
/// Both circles go secondary to selected, as the pills beside them do. They
/// were quiet when off: flat, with no edge, so they sat apart from every other
/// button here and seemed to change size when switched on.
private struct PianoRollControls: View {
    @Bindable var viewModel: CreateKotekViewModel

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    halves
                    eraser
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            AppIconButton(
                systemImage: "pianokeys",
                label: viewModel.showsGangsa ? "Hide gangsa" : "Show gangsa",
                prominence: viewModel.showsGangsa ? .selected : .secondary,
                size: .compact
            ) { viewModel.showsGangsa.toggle() }
                .accessibilityAddTraits(viewModel.showsGangsa ? .isSelected : [])
        }
    }

    private var halves: some View {
        AppSwitcher(
            options: [KotekanHalf.polos, .sangsih],
            // Not drawn as selected while erasing: the half stays remembered.
            selection: viewModel.tool == .notes ? viewModel.writing : nil,
            title: \.title,
            dot: { $0 == .polos ? Theme.polosVoice : Theme.sangsihVoice },
            tint: { $0 == .polos ? Theme.polosVoice : Theme.sangsihVoice },
            style: .pills
        ) {
            viewModel.writing = $0
            viewModel.tool = .notes
        }
    }

    /// The Delete tool: taps take out whatever is under the finger instead of
    /// writing. Tapping a stroke in the notes tool still removes it too — this
    /// is for clearing several without one stray tap writing a new one.
    private var eraser: some View {
        let selected = viewModel.tool == .erase
        return AppIconButton(
            systemImage: "eraser",
            label: "Delete",
            prominence: selected ? .selected : .secondary,
            size: .compact
        ) { viewModel.tool = selected ? .notes : .erase }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Grid

private struct PianoRollGrid: View {
    let viewModel: CreateKotekViewModel
    /// The overview over the gangsa: every row fits, nothing is edited, and a
    /// tap opens the full roll.
    let compact: Bool

    @State private var pinchStart: CGFloat?
    @State private var scroll = ScrollPosition(edge: .leading)
    /// Where the scroll view is, kept out of Observation: written on every
    /// scroll frame, and only read when the line changes bar.
    @State private var offset = ScrollOffset()

    private let labelWidth: CGFloat = 28
    private let rulerHeight: CGFloat = 22
    private let laneHeight: CGFloat = 28
    /// Room before tick 0, so a gong on the downbeat shows its whole ring
    /// instead of half of it.
    private let lead: CGFloat = 12

    /// At zoom 1 a quarter cell and a row are each a comfortable tap (HIG's
    /// 44pt). The roll used to open fitting four bars and every row on
    /// screen, which left cells too small to hit on a phone.
    private static let pointsPerQuarter: CGFloat = 48
    private static let rowHeight: CGFloat = 44
    static let minZoom: CGFloat = 0.3
    static let maxZoom: CGFloat = 2

    var body: some View {
        let draft = viewModel.draft
        // Read here, in body, so Observation sees them. A Canvas closure runs
        // at draw time, outside the tracking body sets up.
        let notes = draft.notes
        let colotomic = draft.colotomic
        let length = draft.lengthTicks
        let timeline = draft.timelineTicks
        let timelineBars = draft.timelineBars
        let snap = viewModel.snap
        let writing = viewModel.writing
        let rows = viewModel.keyCount
        let zoom = viewModel.zoom

        GeometryReader { geo in
            let visible = max(1, geo.size.width - (compact ? 0 : labelWidth))
            let fitAll = visible / CGFloat(timelineBars * 4)
            let ppq = max(fitAll, Self.pointsPerQuarter * zoom)
            let pxPerTick = ppq / CGFloat(KotekanDraft.ticksPerQuarter)
            let width = CGFloat(timeline) * pxPerTick
            // Never shorter than fits: zoomed out, the rows fill the height
            // rather than leave a gap under them.
            let fitRows = max(1, (geo.size.height - rulerHeight - laneHeight) / CGFloat(rows))
            // The overview shows every row however thin; the editor never
            // goes below 10pt, and scrolls instead.
            let rowHeight = compact ? fitRows : max(10, fitRows, Self.rowHeight * zoom)

            // Vertical outside horizontal, so the key labels scroll up and
            // down with their rows but stay put sideways.
            // shortcut: the ruler scrolls off with the rows; pin it if that
            // gets in the way.
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    // Not in the overview: the gangsa under it says which
                    // bilah each row is. It was shown there for a while, set
                    // small to fit, and only took width from the roll.
                    if !compact {
                        VStack(spacing: 0) {
                            keyLabels(rows: rows, rowHeight: rowHeight)
                            Image(systemName: "circle.circle")
                                .font(.symbol(11, weight: .semibold))
                                .foregroundStyle(Theme.stone)
                                .frame(height: laneHeight)
                                .accessibilityLabel("Gong, kempur, klentong and kajar")
                        }
                        .padding(.top, rulerHeight)
                        .frame(width: labelWidth)
                    }

                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            PianoRollRuler(bars: timelineBars, pxPerTick: pxPerTick)
                                .frame(height: rulerHeight)
                                .padding(.leading, lead)
                                .contentShape(Rectangle())
                                // Scrubs from the first touch: a tap puts the
                                // line there, a drag carries it. The roll
                                // still scrolls from the grid below.
                                .gesture(
                                    DragGesture(minimumDistance: 0).onChanged { value in
                                        viewModel.seek(toTick: Int((value.location.x - lead) / pxPerTick))
                                    }
                                )
                                .accessibilityElement()
                                .accessibilityLabel("Playhead")
                                .accessibilityAdjustableAction { direction in
                                    let step = direction == .increment ? snap.ticks : -snap.ticks
                                    viewModel.seek(toTick: Int(viewModel.playhead) + step)
                                }
                            PianoRollCanvas(
                                notes: notes,
                                colotomic: colotomic,
                                lengthTicks: timeline,
                                patternTicks: length,
                                snapTicks: snap.ticks,
                                writing: writing,
                                rows: rows,
                                laneHeight: laneHeight,
                                lead: lead,
                                pxPerTick: pxPerTick
                            )
                            .frame(height: rowHeight * CGFloat(rows) + laneHeight)
                            // Inside the tap below, so a tap on a grip still
                            // reaches it and takes the stroke out.
                            .overlay(alignment: .topLeading) {
                                if viewModel.tool == .notes, !compact {
                                    NoteLengthHandles(
                                        draft: draft,
                                        notes: notes.filter { $0.half == writing },
                                        rings: KotekanDraft.rings(notes, patternTicks: length),
                                        rows: rows,
                                        rowHeight: rowHeight,
                                        lead: lead,
                                        pxPerTick: pxPerTick,
                                        snapTicks: snap.ticks
                                    )
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard !compact else { viewModel.showsGangsa = false
                                    return
                                }
                                tap(
                                    at: CGPoint(x: location.x - lead, y: location.y),
                                    rows: rows,
                                    rowHeight: rowHeight,
                                    pxPerTick: pxPerTick
                                )
                            }
                        }
                        .frame(width: width + lead)
                        .overlay(alignment: .topLeading) {
                            PreviewPlayhead(viewModel: viewModel, pxPerTick: pxPerTick)
                                .padding(.leading, lead)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollPosition($scroll)
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                        offset.x = x
                    }
                    // Keep the line on screen — playing, or stepping through a
                    // recording. Page by bar, as a DAW does, not glued to the line.
                    .onChange(of: viewModel.playheadBar) { _, bar in
                        let barWidth = CGFloat(KotekanDraft.ticksPerBar) * pxPerTick
                        let x = CGFloat(bar) * barWidth
                        guard x < offset.x || x + min(barWidth, visible) > offset.x + visible + 1 else { return }
                        withAnimation(.easeInOut(duration: 0.25)) { scroll.scrollTo(x: x) }
                    }
                }
            }
            .scrollDisabled(compact)
            .scrollBounceBehavior(.basedOnSize)
            // On the outer scroll view, not the horizontal one: there the
            // pinch lost to the scroll's own pan and the roll never zoomed.
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? zoom
                        pinchStart = start
                        viewModel.zoom = (start * value.magnification).clamped(to: Self.minZoom, Self.maxZoom)
                    }
                    .onEnded { _ in pinchStart = nil }
            )
        }
        .background(Theme.deep.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.radius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .accessibilityActions {
            if compact {
                Button("Edit piano roll") { viewModel.showsGangsa = false }
            }
        }
    }

    private func keyLabels(rows: Int, rowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach((0 ..< rows).reversed(), id: \.self) { key in
                Text("\(key + 1)")
                    .font(.sans(min(11, max(7, rowHeight * 0.75)), weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Theme.stone)
                    .frame(height: rowHeight)
            }
        }
    }

    private func tap(at location: CGPoint, rows: Int, rowHeight: CGFloat, pxPerTick: CGFloat) {
        guard location.x >= 0 else { return }
        let position = Int(location.x / pxPerTick)
        let row = Int(location.y / rowHeight)
        guard (0 ..< rows).contains(row) else { return }
        let key = rows - 1 - row
        let draft = viewModel.draft

        switch viewModel.tool {
        case .erase:
            viewModel.editRoll { draft.eraseNote(key: key, at: position, preferring: viewModel.writing) }

        case .notes:
            let before = draft.notes.count
            viewModel.editRoll { draft.toggle(half: viewModel.writing, key: key, at: position, snap: viewModel.snap) }
            // Sound what was written, not what was taken out.
            if draft.notes.count >= before { viewModel.audition(key) }
        }
    }
}

/// The grip on the end of each stroke of the half being written: where the
/// bilah is damped. A stroke rings to the half's next one by itself; drag the
/// grip back to damp it sooner, a block at a time, or out again to
/// let it ring. Grips rather than a drag anywhere on a stroke, because a drag
/// on the grid is how the roll scrolls.
///
/// A white line on the stroke's beige damp cap (`PianoRollCanvas.drawNote`),
/// edged in a deeper beige so it holds against it. It was `Theme.cream`, which
/// the Nawa Sanga palette repointed to Ireng: a black line on a red or blue
/// block that read as part of the drawing rather than something to take hold of.
private struct NoteLengthHandles: View {
    let draft: KotekanDraft
    let notes: [DraftNote]
    let rings: [DraftNote.ID: DraftRing]
    let rows: Int
    let rowHeight: CGFloat
    let lead: CGFloat
    let pxPerTick: CGFloat
    let snapTicks: Int

    private static let gripEdge = Color(hex: 0xC9B79A)

    /// The stroke being dragged, how long it rang when the drag began, and
    /// its damp point then (nil: the default) to put back for the undo step.
    @State private var dragging: (id: DraftNote.ID, from: Int, stored: Int?)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(notes) { note in
                let row = rows - 1 - note.key
                let ring = rings[note.id]?.ticks ?? snapTicks
                if row >= 0 {
                    Capsule()
                        .fill(.white)
                        .overlay(Capsule().strokeBorder(Self.gripEdge, lineWidth: 0.75))
                        .frame(width: 3.5, height: max(6, rowHeight * 0.4))
                        .frame(width: 20, height: rowHeight)
                        .contentShape(Rectangle())
                        .gesture(drag(note, ring: ring))
                        .accessibilityElement()
                        .accessibilityLabel("Damp point")
                        .accessibilityAdjustableAction { direction in
                            let step = direction == .increment ? KotekanDraft.dampStep : -KotekanDraft.dampStep
                            draft.edit { draft.resize(note.id, length: ring + step) }
                        }
                        .position(
                            // On the cap's middle: the note ends a point
                            // short of its tick, and the cap runs back from there.
                            x: lead + CGFloat(note.tick + ring) * pxPerTick - 1
                                - PianoRollCanvas.capWidth(rowHeight: rowHeight) / 2,
                            y: (CGFloat(row) + 0.5) * rowHeight
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func drag(_ note: DraftNote, ring: Int) -> some Gesture {
        // Global space: the grip moves as the stroke grows, and a translation
        // measured in its own space would chase it.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let from = dragging?.from ?? ring
                if dragging == nil { dragging = (note.id, from, note.length) }
                let raw = Double(from) + Double(value.translation.width / pxPerTick)
                // A block at a time, whatever the snap (`KotekanDraft.dampStep`).
                let step = Double(KotekanDraft.dampStep)
                let length = Int((raw / step).rounded() * step)
                draft.resize(note.id, length: length)
            }
            .onEnded { _ in
                guard let d = dragging else { return }
                dragging = nil
                // One undo step for the whole drag, not one per frame: put the
                // old damp point back, then write the new one through `edit`.
                let final = draft.notes.first { $0.id == d.id }?.length
                draft.setDampPoint(d.id, d.stored)
                draft.edit { draft.setDampPoint(d.id, final) }
            }
    }
}

/// Grid lines and strokes, drawn like a DAW's piano roll. One Canvas rather
/// than a view per cell: a 1/32 grid over 32 bars is 10,240 cells. The review
/// screen draws the finished figure with it too.
struct PianoRollCanvas: View {
    let notes: [DraftNote]
    let colotomic: [DraftColotomic]
    let lengthTicks: Int
    /// Where the figure ends. The timeline runs on past it, shaded.
    let patternTicks: Int
    let snapTicks: Int
    /// The half being written, drawn on top; the other is dimmed. nil draws
    /// both at full strength — the review, where neither is being edited.
    let writing: KotekanHalf?
    let rows: Int
    let laneHeight: CGFloat
    let lead: CGFloat
    let pxPerTick: CGFloat

    var body: some View {
        let rings = KotekanDraft.rings(notes, patternTicks: patternTicks)
        Canvas { ctx, size in
            ctx.translateBy(x: lead, y: 0)
            let rowsHeight = size.height - laneHeight
            let rowHeight = rowsHeight / CGFloat(rows)

            for row in 0 ..< rows where row % 2 == 1 {
                let band = CGRect(x: 0, y: CGFloat(row) * rowHeight, width: size.width, height: rowHeight)
                ctx.fill(Path(band), with: .color(Theme.cream.opacity(0.03)))
            }

            func vline(_ tick: Int, _ color: Color, _ width: CGFloat) {
                let x = CGFloat(tick) * pxPerTick
                ctx.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(color))
            }
            // Snap lines only where they are far enough apart to aim at.
            if CGFloat(snapTicks) * pxPerTick >= 6 {
                for tick in stride(from: 0, to: lengthTicks, by: snapTicks) {
                    vline(tick, Theme.cream.opacity(0.06), 1)
                }
            }
            for tick in stride(from: 0, to: lengthTicks, by: KotekanDraft.ticksPerQuarter) {
                vline(tick, Theme.cream.opacity(0.14), 1)
            }
            for tick in stride(from: 0, to: lengthTicks, by: KotekanDraft.ticksPerBar) {
                vline(tick, Theme.gold.opacity(0.55), 1.5)
            }

            // Past the end of the figure: still writable — a note there
            // stretches the figure to reach it — but shaded, so the loop point
            // is never a guess.
            let end = CGFloat(patternTicks) * pxPerTick
            ctx.fill(
                Path(CGRect(x: end, y: 0, width: size.width - end, height: size.height)),
                with: .color(.black.opacity(0.28))
            )
            ctx.fill(Path(CGRect(x: end - 1, y: 0, width: 2.5, height: size.height)), with: .color(Theme.gold))

            // The half you are not writing goes underneath, dimmed — visible
            // enough to interlock against, never mistaken for your own.
            let ordered = notes.sorted { ($0.half == writing ? 1 : 0) < ($1.half == writing ? 1 : 0) }
            for note in ordered {
                let row = rows - 1 - note.key
                guard row >= 0 else { continue }
                var c = ctx
                c.opacity = writing == nil || note.half == writing ? 1 : 0.35
                Self.drawNote(
                    c,
                    at: CGPoint(x: CGFloat(note.tick) * pxPerTick, y: CGFloat(row) * rowHeight),
                    ring: rings[note.id] ?? DraftRing(ticks: snapTicks, damps: false),
                    pxPerTick: pxPerTick,
                    rowHeight: rowHeight,
                    color: note.half == .polos ? Theme.polosVoice : Theme.sangsihVoice
                )
            }

            // The colotomic lane.
            let laneMid = rowsHeight + laneHeight / 2
            ctx.fill(
                Path(CGRect(x: 0, y: rowsHeight, width: size.width, height: 1)),
                with: .color(Theme.cream.opacity(0.12))
            )
            // Then each written stroke: its line through the rows tinted, and
            // its circle on that line in the lane. Gong outermost, so three on
            // one beat nest instead of hiding each other.
            let byTick = Dictionary(grouping: colotomic, by: \.tick)
            for (tick, hits) in byTick {
                let x = CGFloat(tick) * pxPerTick
                let instruments = Set(hits.map(\.instrument))
                let loudest = ColotomicInstrument.allCases.first { instruments.contains($0) }!
                ctx.fill(
                    Path(CGRect(x: x - 1, y: 0, width: 2, height: rowsHeight)),
                    with: .color(loudest.color.opacity(0.45))
                )
                for instrument in instruments {
                    ColotomicMark.draw(instrument, in: ctx, at: CGPoint(x: x, y: laneMid), scale: 1)
                }
            }
        }
    }
}

extension PianoRollCanvas {
    /// The damp cap along the time axis, the grip's place. Wider than the
    /// waterfall's, which is two fifths of its stroke: it is held and dragged
    /// here.
    static func capWidth(rowHeight: CGFloat) -> CGFloat {
        max(6, (rowHeight - 4) * 0.2)
    }

    /// One note as the waterfall draws it, lying down: a pill in the voice's
    /// colour where the bilah is struck, and the cream stem, outlined in
    /// beige, out to where it stops ringing, capped there in beige where the
    /// hand damps it. The designer's waterfall note (November 2026).
    ///
    /// The pill is one block, a quarter, whatever the snap — the size of the
    /// cell it was tapped into, and the shortest a stroke rings. It was the
    /// waterfall's stroke turned on its side, a sliver a few points wide, and
    /// too thin to see or hit.
    ///
    /// It was first a block in the voice's colour as long as the ring, a dark
    /// cap on its end — a second drawing of the same note, and the colour ran
    /// right across a rest the player had left empty.
    ///
    /// The waterfall draws no stem on a stroke struck again on the same bilah
    /// (nothing to damp); here it still runs, uncapped, so its grip has
    /// somewhere to be when the player wants it stopped sooner.
    static func drawNote(
        _ ctx: GraphicsContext,
        at origin: CGPoint,
        ring: DraftRing,
        pxPerTick: CGFloat,
        rowHeight: CGFloat,
        color: Color
    ) {
        let h = rowHeight - 4
        let top = origin.y + 2
        let start = origin.x + 1
        let block = max(4, CGFloat(Subdivision.quarter.ticks) * pxPerTick - 2)
        let end = max(start + 4, origin.x + CGFloat(ring.ticks) * pxPerTick - 1)
        let cap = ring.damps ? capWidth(rowHeight: rowHeight) : 0

        if end > start + block {
            let stemH = h * 0.7
            let stemY = top + (h - stemH) / 2
            // Into the pill a little, so the stem meets it without a seam.
            let foot = start + block - 2
            let r = stemH * 0.1
            let outline = UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r)
                .path(in: CGRect(x: foot, y: stemY, width: end - foot, height: stemH))
            ctx.fill(outline, with: .color(Theme.dampBeige))
            let edge = max(1, h * 0.03)
            let inner = CGRect(
                x: foot,
                y: stemY + edge,
                width: max(0, end - foot - (ring.damps ? min(cap, end - foot) : edge)),
                height: stemH - 2 * edge
            )
            ctx.fill(Path(inner), with: .color(Theme.stemCream))
        }

        // Shorter only where the next stroke comes sooner than a block,
        // which only a sensor take can write.
        let width = min(block, end - start)
        let stroke = CGRect(x: start, y: top, width: width, height: h)
        ctx.fill(Path(roundedRect: stroke, cornerRadius: min(width, h) * 0.3), with: .color(color))
    }
}

extension ColotomicInstrument {
    /// Four hues apart from each other and from the two halves (blue and
    /// purple). The Play screen's colotomic family — cream, amber, stone — is
    /// meant to recede under the voices; here the player writes these and has
    /// to tell them apart at a glance, so they stand out instead.
    var color: Color {
        switch self {
        // The gold and green the rank ladder used, kept by value when the
        // ladder went.
        case .gong: Color(hex: 0xE8B44A)
        case .kempur: Color(hex: 0x4FB3A9)
        case .kajar: .white
        case .klentong: Color(hex: 0xE0765A)
        }
    }
}

/// How each instrument is drawn: a gong as a big ring, a kempur and a klentong
/// smaller ones, a kajar a dot — sized like the sounds, and nested when they coincide.
struct ColotomicMark: View {
    let instrument: ColotomicInstrument
    var scale: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            Self.draw(instrument, in: ctx, at: CGPoint(x: size.width / 2, y: size.height / 2), scale: scale)
        }
        .frame(width: 20 * scale, height: 20 * scale)
    }

    static func draw(_ instrument: ColotomicInstrument, in ctx: GraphicsContext, at p: CGPoint, scale: CGFloat) {
        func circle(_ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        switch instrument {
        case .gong: ctx.stroke(circle(9 * scale), with: .color(instrument.color), lineWidth: 2.5 * scale)
        case .kempur: ctx.stroke(circle(7 * scale), with: .color(instrument.color), lineWidth: 2.2 * scale)
        case .klentong: ctx.stroke(circle(5.5 * scale), with: .color(instrument.color), lineWidth: 2 * scale)
        case .kajar: ctx.fill(circle(4 * scale), with: .color(instrument.color))
        }
    }
}

/// Bar numbers over the bar lines, a tick on every quarter.
struct PianoRollRuler: View {
    let bars: Int
    let pxPerTick: CGFloat

    var body: some View {
        let barWidth = CGFloat(KotekanDraft.ticksPerBar) * pxPerTick
        let beatWidth = barWidth / 4

        ZStack(alignment: .topLeading) {
            ForEach(0 ..< bars, id: \.self) { bar in
                ForEach(0 ..< 4, id: \.self) { beat in
                    let x = CGFloat(bar) * barWidth + CGFloat(beat) * beatWidth
                    Rectangle()
                        .fill(beat == 0 ? Theme.gold : Theme.cream.opacity(0.25))
                        .frame(width: 1, height: beat == 0 ? 22 : 6)
                        .offset(x: x, y: beat == 0 ? 0 : 16)
                }
                Text("\(bar + 1)")
                    .font(.sans(11, weight: .bold))
                    .foregroundStyle(Theme.goldText)
                    .offset(x: CGFloat(bar) * barWidth + 4, y: 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private final class ScrollOffset {
    var x: CGFloat = 0
}

/// The line, with GarageBand's flag on the ruler to grab it by. Its own view
/// so the per-frame move redraws only this. Shown always — it is where play
/// and record start from. Drawn only: the drag is the ruler's, so a finger
/// near the flag gets it too.
struct PreviewPlayhead: View {
    let viewModel: CreateKotekViewModel
    let pxPerTick: CGFloat

    private static let flagWidth: CGFloat = 14

    var body: some View {
        let color = viewModel.recording ? Theme.miss : Theme.cream
        VStack(spacing: 0) {
            PlayheadFlag()
                .fill(color)
                .frame(width: Self.flagWidth, height: 16)
                .padding(.top, 3)
            Rectangle()
                .fill(color)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: Self.flagWidth)
        .offset(x: CGFloat(viewModel.playhead) * pxPerTick - Self.flagWidth / 2)
        .allowsHitTesting(false)
    }
}

/// A rectangle with a point at the bottom, the point on the line.
private struct PlayheadFlag: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder = rect.maxY - rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: shoulder))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: shoulder))
        path.closeSubpath()
        return path
    }
}

// MARK: - Transport

/// Undo · redo, stop · play/pause, and the clock — a DAW's transport
/// bar. Its own view because the clock reads the playhead, which moves every
/// frame. While recording, play shows pause and stops the take. The record
/// button alone says it is recording — a sensor status here (a glyph, then
/// words) only read as noise.
private struct PianoRollTransport: View {
    let viewModel: CreateKotekViewModel

    var body: some View {
        let draft = viewModel.draft

        HStack(spacing: 14) {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                AppIconButton(systemImage: "arrow.uturn.backward", label: "Undo", size: .compact) { viewModel.undo() }
                    .disabled(!draft.canUndo)
                AppIconButton(systemImage: "arrow.uturn.forward", label: "Redo", size: .compact) { viewModel.redo() }
                    .disabled(!draft.canRedo)
            }

            divider

            HStack(spacing: 10) {
                AppIconButton(systemImage: "stop.fill", label: "Back to start", size: .compact) {
                    viewModel.stopPreview()
                }
                let running = viewModel.playing || viewModel.recording
                AppIconButton(
                    systemImage: running ? "pause.fill" : "play.fill",
                    label: running ? "Pause" : "Play",
                    // Secondary: one red button per screen, and that is Next.
                    prominence: .secondary,
                    size: .compact
                ) { viewModel.togglePlay() }
                    .disabled(draft.isEmpty && !running)
                AppIconButton(systemImage: "forward.end", label: "Skip a step", size: .compact) {
                    viewModel.skip()
                }
                .disabled(viewModel.recording)
            }

            divider

            PlayheadClock(viewModel: viewModel)
            Spacer(minLength: 0)
        }
        .frame(height: 44)
    }

    private var divider: some View {
        Rectangle().fill(Theme.cream.opacity(0.15)).frame(width: 1, height: 28)
    }
}

/// Where the playhead is, and how long one pass of the figure lasts. Its own
/// view: it reads the playhead, which moves every frame.
struct PlayheadClock: View {
    let viewModel: CreateKotekViewModel

    var body: some View {
        let draft = viewModel.draft
        HStack(spacing: 4) {
            Text(Self.format(draft.ms(atTick: viewModel.playhead)))
                .foregroundStyle(Theme.cream)
            Text("/ \(Self.format(draft.ms(atTick: Double(draft.lengthTicks))))")
                .foregroundStyle(Theme.stone)
        }
        .font(.sans(14, weight: .medium).monospacedDigit())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    /// m:ss.mmm
    static func format(_ ms: Double) -> String {
        let total = Int(ms)
        return String(format: "%d:%02d.%03d", total / 60000, total / 1000 % 60, total % 1000)
    }
}

/// The figure's tempo, typed. It was here as a bare number box in the
/// transport, and went when the transport was rebuilt (October 2026), which
/// left every new figure at 100 BPM and an opened one stuck at its own. Typed
/// rather than a menu or a − / + stepper: 88 → 160 is one entry, not
/// seventy-two taps.
///
/// It writes through while the number is plausible (see `typedFloor`), and
/// settles to the nearest allowed value when the field is left. Drawn as the menus beside it are, a white capsule on a
/// Garis
/// edge, so the row reads as one set of controls.
private struct BPMField: View {
    @Binding var bpm: Int

    @State private var text = ""
    @FocusState private var focused: Bool

    private let size = AppButtonSize.compact

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .focused($focused)
                .multilineTextAlignment(.trailing)
                .font(.sans(size.labelPoints, weight: .semibold).monospacedDigit())
                .frame(width: 30)
                .accessibilityLabel("Beats per minute")
            Text("BPM")
                .font(.sans(size.labelPoints - 2, weight: .medium))
                .foregroundStyle(Theme.stone)
        }
        .foregroundStyle(Theme.cream)
        .padding(.horizontal, size.horizontalPadding - 8)
        .frame(minHeight: size.height)
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .tactile(
            Capsule(),
            fill: Theme.glassTint,
            outline: focused ? Theme.primary : Theme.hairline,
            outlineWidth: focused ? 2 : 1,
            base: Theme.hairline,
            depth: size.depth
        )
        .fixedSize()
        .onAppear { text = "\(bpm)" }
        .onChange(of: text) { _, new in
            let digits = String(new.filter(\.isNumber).prefix(3))
            if digits != new { text = digits }
            if let v = Int(digits), KotekanDraft.bpmRange.contains(v), v >= Self.typedFloor { bpm = v }
        }
        .onChange(of: bpm) { _, v in
            if !focused { text = "\(v)" }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onSubmit(commit)
        // A number pad has no return key; this is the way out of it.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    /// Below this a number is taken as still being typed: "1" on the way to
    /// "120" would otherwise run the preview at 1 BPM for a keystroke.
    private static let typedFloor = 20

    private func commit() {
        bpm = (Int(text) ?? bpm).clamped(to: KotekanDraft.bpmRange.lowerBound, KotekanDraft.bpmRange.upperBound)
        text = "\(bpm)"
    }
}

/// Arms the sensors. Red, and filled while recording, so it is never a
/// question whether a hit on the gangsa is being written down.
///
/// Not an `AppButton`: its primary sets the label heavy and uppercase like
/// NEXT, so "Recording" jumped in weight and case. Like the half pills, only
/// the fill changes. Now icon-only (the label is dropped), so it's a circle.
private struct RecordButton: View {
    let recording: Bool
    /// Looks off, but still takes the tap — to say why it is off.
    var looksEnabled = true
    let action: () -> Void

    var body: some View {
        let prominence: AppButton.Prominence = recording ? .primary : .secondary
        Button(action: action) {
            Image(systemName: recording ? "stop.fill" : "circle.fill")
                .font(.symbol(AppButtonSize.regular.symbolPoints, weight: .semibold))
                .foregroundStyle(prominence.labelColor(tint: Theme.miss, enabled: looksEnabled))
                .appControlSurface(
                    size: .regular,
                    shape: .circle,
                    prominence: prominence,
                    tint: recording ? Theme.miss : nil
                )
        }
        .buttonStyle(AppButtonStyle())
        .accessibilityLabel(recording ? "Stop recording" : "Record")
    }
}

/// Record, off without a sensor: recording listens to the controller, and
/// without one there is nothing to listen to. Not `.disabled`: a disabled
/// button takes no tap, and the tap is where it says why and how to connect
/// — the kotekan picker's sensor chip says it the same way.
private struct RecordControl: View {
    let viewModel: CreateKotekViewModel
    @Environment(AppState.self) private var app
    @State private var explaining = false

    var body: some View {
        let available = viewModel.hasSensor || viewModel.recording
        RecordButton(recording: viewModel.recording, looksEnabled: available) {
            if available { viewModel.toggleRecording() } else { explaining = true }
        }
        .popover(isPresented: $explaining) {
            // Connecting leaves this screen, and the draft with it, so it is
            // only offered before anything has been written.
            if viewModel.draft.isEmpty {
                SensorTip(
                    title: "Recording needs a sensor",
                    message: "Connect your sensor controller to record as you play. Or tap the gangsa below to write notes one by one.",
                    onConnect: { app.openControllerSetup(returnTo: .createKotek) },
                    onDismiss: { explaining = false }
                )
            } else {
                SensorTip(
                    title: "Recording needs a sensor",
                    message: "Tap the gangsa below to write notes one by one. To record from a sensor, save this kotek first, then connect one.",
                    onConnect: nil,
                    onDismiss: { explaining = false }
                )
            }
        }
    }
}
