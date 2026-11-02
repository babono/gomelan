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
                    RecordButton(recording: viewModel.recording) { viewModel.toggleRecording() }
                    AppButton(title: "Next", prominence: .primary) { viewModel.review() }
                        .disabled(draft.isEmpty)
                }
            }
            .frame(minHeight: 50)

            HStack(spacing: 10) {
                PianoRollControls(viewModel: viewModel)
                AppMenuPicker<Double>.tempo($viewModel.tempoScale)
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
                TouchGangsa(viewModel: viewModel)
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
private struct PianoRollControls: View {
    @Bindable var viewModel: CreateKotekViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                halves
                divider
                eraser
                divider
                AppIconButton(
                    systemImage: "pianokeys",
                    label: viewModel.showsGangsa ? "Hide gangsa" : "Show gangsa",
                    prominence: viewModel.showsGangsa ? .selected : .quiet,
                    size: .compact
                ) { viewModel.showsGangsa.toggle() }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var halves: some View {
        AppSwitcher(
            options: [KotekanHalf.polos, .sangsih],
            // Not drawn as selected while erasing: the half stays remembered.
            selection: viewModel.tool == .notes ? viewModel.writing : nil,
            title: \.title,
            dot: { $0 == .polos ? Theme.polosVoice : Theme.sangsihVoice },
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
        return Button {
            viewModel.tool = selected ? .notes : .erase
        } label: {
            Image(systemName: "eraser")
                .font(.symbol(AppButtonSize.compact.symbolPoints, weight: .semibold))
                .foregroundStyle(selected ? Theme.onGlassFill : Theme.cream)
                // A tool that is on is Ireng, one that is off Krem — the design
                // system's tool buttons. Merah is for Next.
                .appControlSurface(size: .compact, shape: .circle, prominence: selected ? .selected : .quiet)
        }
        .buttonStyle(AppButtonStyle())
        .accessibilityLabel("Delete")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var divider: some View {
        Rectangle().fill(Theme.cream.opacity(0.15)).frame(width: 1, height: 24)
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
        let timeline = KotekanDraft.timelineTicks
        let snap = viewModel.snap
        let writing = viewModel.writing
        let rows = viewModel.keyCount
        let zoom = viewModel.zoom

        GeometryReader { geo in
            let visible = max(1, geo.size.width - labelWidth)
            let fitAll = visible / CGFloat(KotekanDraft.timelineBars * 4)
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
                    VStack(spacing: 0) {
                        // Too thin to read in the overview.
                        keyLabels(rows: rows, rowHeight: rowHeight).opacity(compact ? 0 : 1)
                        Image(systemName: "circle.circle")
                            .font(.symbol(11, weight: .semibold))
                            .foregroundStyle(Theme.stone)
                            .frame(height: laneHeight)
                            .accessibilityLabel("Gong, kempur, klentong and kajar")
                    }
                    .padding(.top, rulerHeight)
                    .frame(width: labelWidth)

                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            PianoRollRuler(bars: KotekanDraft.timelineBars, pxPerTick: pxPerTick)
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
                    .font(.sans(11, weight: .semibold))
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
            draft.edit { draft.eraseNote(key: key, at: position, preferring: viewModel.writing) }

        case .notes:
            let before = draft.notes.count
            draft.edit { draft.toggle(half: viewModel.writing, key: key, at: position, snap: viewModel.snap) }
            // Sound what was written, not what was taken out.
            if draft.notes.count >= before { viewModel.audition(key) }
        }
    }
}

/// The grip on the end of each stroke of the half being written: drag it to
/// make the stroke longer or shorter, in steps of the snap value. Grips rather
/// than a drag anywhere on a stroke, because a drag on the grid is how the roll
/// scrolls.
private struct NoteLengthHandles: View {
    let draft: KotekanDraft
    let notes: [DraftNote]
    let rows: Int
    let rowHeight: CGFloat
    let lead: CGFloat
    let pxPerTick: CGFloat
    let snapTicks: Int

    /// The stroke being dragged, and its length when the drag began.
    @State private var dragging: (id: DraftNote.ID, from: Int)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(notes) { note in
                let row = rows - 1 - note.key
                if row >= 0 {
                    Capsule()
                        .fill(Theme.cream.opacity(0.85))
                        .frame(width: 3, height: max(6, rowHeight * 0.45))
                        .frame(width: 20, height: rowHeight)
                        .contentShape(Rectangle())
                        .gesture(drag(note))
                        .accessibilityElement()
                        .accessibilityLabel("Stroke length")
                        .accessibilityAdjustableAction { direction in
                            let step = direction == .increment ? snapTicks : -snapTicks
                            draft.edit { draft.resize(note.id, length: max(snapTicks, note.length + step)) }
                        }
                        .position(
                            x: lead + CGFloat(note.tick + note.length) * pxPerTick - 6,
                            y: (CGFloat(row) + 0.5) * rowHeight
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func drag(_ note: DraftNote) -> some Gesture {
        // Global space: the grip moves as the stroke grows, and a translation
        // measured in its own space would chase it.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let from = dragging?.from ?? note.length
                if dragging == nil { dragging = (note.id, from) }
                let raw = Double(from) + Double(value.translation.width / pxPerTick)
                let length = max(snapTicks, Int((raw / Double(snapTicks)).rounded()) * snapTicks)
                draft.resize(note.id, length: length)
            }
            .onEnded { _ in
                guard let d = dragging else { return }
                dragging = nil
                // One undo step for the whole drag, not one per frame: put the
                // old length back, then write the new one through `edit`.
                let final = draft.length(of: d.id) ?? d.from
                draft.resize(d.id, length: d.from)
                draft.edit { draft.resize(d.id, length: final) }
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
                let rect = CGRect(
                    x: CGFloat(note.tick) * pxPerTick + 1,
                    y: CGFloat(row) * rowHeight + 2,
                    width: max(4, CGFloat(note.length) * pxPerTick - 2),
                    height: rowHeight - 4
                )
                let color = note.half == .polos ? Theme.polosVoice : Theme.sangsihVoice
                let active = writing == nil || note.half == writing
                let block = Path(roundedRect: rect, cornerRadius: 4)
                ctx.fill(block, with: .color(color.opacity(active ? 0.9 : 0.3)))
                if active {
                    ctx.stroke(block, with: .color(Theme.cream.opacity(0.5)), lineWidth: 1)
                }
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
                AppIconButton(systemImage: "arrow.uturn.backward", label: "Undo", size: .compact) { draft.undo() }
                    .disabled(!draft.canUndo)
                AppIconButton(systemImage: "arrow.uturn.forward", label: "Redo", size: .compact) { draft.redo() }
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

/// Arms the sensors. Red, and filled while recording, so it is never a
/// question whether a hit on the gangsa is being written down.
///
/// Not an `AppButton`: its primary sets the label heavy and uppercase like
/// NEXT, so "Recording" jumped in weight and case. Like the half pills, only
/// the fill changes. Now icon-only (the label is dropped), so it's a circle.
private struct RecordButton: View {
    let recording: Bool
    let action: () -> Void

    var body: some View {
        let prominence: AppButton.Prominence = recording ? .primary : .secondary
        Button(action: action) {
            Image(systemName: recording ? "stop.fill" : "circle.fill")
                .font(.symbol(AppButtonSize.regular.symbolPoints, weight: .semibold))
                .foregroundStyle(prominence.labelColor(tint: Theme.miss, enabled: true))
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
