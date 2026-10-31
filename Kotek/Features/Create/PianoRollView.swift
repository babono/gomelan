//
//  PianoRollView.swift
//  Kotek
//
//  The Create Kotek editor: a piano roll with bilah for rows, modelled on a
//  DAW's editor (Signal, CapCut's timeline). Tap to write a stroke, tap it
//  again to take it out. The grid scrolls sideways and pinches to zoom; the
//  snap value sets the width of a new stroke and where it lands, and the grip
//  on a stroke's end drags it longer or shorter from there.
//
//  Record turns the sensors on and makes the line a cursor: it waits for a
//  hit, writes it there for the half being written, and steps on by the snap
//  value. Rest steps on without writing; a tap on the ruler moves the line.
//
//  Under the rows runs a colotomic lane: gong, kempur, klentong and kajar are written
//  there as circles sitting on the line they sound on, the way a gamelan score
//  video marks them. Nothing sounds under them but what is written.
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
            CreateTopBar(title: "New Kotek") {
                AppIconButton(systemImage: "chevron.left", label: "Back") { viewModel.back() }
            } trailing: {
                RecordButton(recording: viewModel.recording) { viewModel.toggleRecording() }
                AppButton(title: "Next", prominence: .primary) { viewModel.review() }
                    .disabled(draft.isEmpty)
            }

            PianoRollControls(viewModel: viewModel)

            PianoRollGrid(viewModel: viewModel)

            PianoRollTransport(viewModel: viewModel)
        }
        // On top of the safe area, not instead of it: the landscape inset
        // already clears the notch and home indicator. Tight both ways: the
        // tools row needs the width, and fourteen bilah rows need the height.
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Controls row

/// The halves, then the tools: the four colotomic instruments and the eraser,
/// named. The snap menu lives in the transport, which is what leaves this row
/// room for the names. A row too wide for a small phone scrolls rather than
/// squeezing one chip over the next.
private struct PianoRollControls: View {
    @Bindable var viewModel: CreateKotekViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                halves
                divider
                HStack(spacing: 8) {
                    ForEach(ColotomicInstrument.allCases) { tool($0) }
                }
                divider
                eraser
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var halves: some View {
        AppSwitcher(
            options: [KotekanHalf.polos, .sangsih],
            // Not drawn as selected while the roll is writing a colotomic
            // instrument: the half stays remembered.
            selection: viewModel.tool == .notes ? viewModel.writing : nil,
            title: \.title,
            dot: { $0 == .polos ? Theme.polosVoice : Theme.sangsihVoice },
            style: .pills
        ) {
            viewModel.writing = $0
            viewModel.tool = .notes
        }
    }

    /// Arms a colotomic instrument for the next taps. Tapping it again goes
    /// back to writing the half. Drawn like the half pills, so a chosen tool
    /// and a chosen half look the same.
    private func tool(_ instrument: ColotomicInstrument) -> some View {
        let selected = viewModel.tool == .colotomic(instrument)
        return Button {
            viewModel.tool = selected ? .notes : .colotomic(instrument)
        } label: {
            HStack(spacing: 6) {
                ColotomicMark(instrument: instrument, scale: 0.7)
                Text(instrument.title).appLabel(.compact)
            }
            .foregroundStyle(selected ? Theme.onGlassFill : Theme.cream)
            .appControlSurface(size: .compact, shape: .capsule, prominence: selected ? .primary : .secondary)
        }
        .buttonStyle(AppButtonStyle())
        .accessibilityLabel("Add \(instrument.title)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
                .appControlSurface(size: .compact, shape: .circle, prominence: selected ? .primary : .secondary)
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

    /// Points per quarter note. nil until the player pinches: fit four bars, so
    /// it is plain the figure can run on past one.
    @State private var pointsPerQuarter: CGFloat?
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
    private static let maxPointsPerQuarter: CGFloat = 320

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

        GeometryReader { geo in
            let visible = max(1, geo.size.width - labelWidth)
            let fitAll = visible / CGFloat(KotekanDraft.timelineBars * 4)
            let ppq = (pointsPerQuarter ?? visible / 16).clamped(to: fitAll, Self.maxPointsPerQuarter)
            let pxPerTick = ppq / CGFloat(KotekanDraft.ticksPerQuarter)
            let width = CGFloat(timeline) * pxPerTick
            let rowHeight = max(10, (geo.size.height - rulerHeight - laneHeight) / CGFloat(rows))

            HStack(spacing: 0) {
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

                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        PianoRollRuler(bars: KotekanDraft.timelineBars, pxPerTick: pxPerTick)
                            .frame(height: rulerHeight)
                            .padding(.leading, lead)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                viewModel.seek(toTick: Int((location.x - lead) / pxPerTick))
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
                            if viewModel.tool == .notes {
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
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let start = pinchStart ?? ppq
                            pinchStart = start
                            pointsPerQuarter = (start * value.magnification)
                                .clamped(to: fitAll, Self.maxPointsPerQuarter)
                        }
                        .onEnded { _ in pinchStart = nil }
                )
            }
        }
        .background(Theme.deep.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.radius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
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
        let key = (0 ..< rows).contains(row) ? rows - 1 - row : nil
        let draft = viewModel.draft

        switch viewModel.tool {
        case let .colotomic(instrument):
            // An armed instrument writes wherever the finger lands — the lane
            // is where it is drawn, not the only place to aim.
            let before = draft.colotomic.count
            draft.edit { draft.toggleColotomic(instrument, at: position, snap: viewModel.snap) }
            if draft.colotomic.count > before { viewModel.audition(instrument) }

        case .erase:
            // A circle is small; give the finger half a snap or 12pt, whichever
            // is wider.
            let tolerance = max(viewModel.snap.ticks / 2, Int(12 / pxPerTick))
            draft.edit {
                if let key {
                    draft.eraseNote(key: key, at: position, preferring: viewModel.writing)
                } else {
                    draft.eraseColotomic(near: position, tolerance: tolerance)
                }
            }

        case .notes:
            guard let key else { return }
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
                    .foregroundStyle(Theme.gold)
                    .offset(x: CGFloat(bar) * barWidth + 4, y: 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The preview's position, as a line over the grid. Its own view so the
/// per-frame move redraws only this. Shown paused too — that is where play
/// picks up from.
private final class ScrollOffset {
    var x: CGFloat = 0
}

struct PreviewPlayhead: View {
    let viewModel: CreateKotekViewModel
    let pxPerTick: CGFloat

    var body: some View {
        if !viewModel.draft.isSilent || viewModel.recording {
            Rectangle()
                .fill(viewModel.recording ? Theme.miss : Theme.cream)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .offset(x: CGFloat(viewModel.playhead) * pxPerTick - 1)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Transport

/// Undo · redo, stop · play/pause, the tempo, and the clock — a DAW's transport
/// bar. Its own view because the clock reads the playhead, which moves every
/// frame. While recording, play gives way to Rest and the clock to the sensor
/// set-up: nothing is playing, and the line only moves on a hit.
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
                if viewModel.recording {
                    AppButton(title: "Rest", size: .compact) { viewModel.recordRest() }
                        .accessibilityHint("Steps the line on without writing a note")
                } else {
                    AppIconButton(
                        systemImage: viewModel.playing ? "pause.fill" : "play.fill",
                        label: viewModel.playing ? "Pause" : "Play",
                        prominence: .primary,
                        size: .compact
                    ) { viewModel.togglePlay() }
                        .disabled(draft.isSilent)
                }
            }

            divider

            HStack(spacing: 10) {
                NumberField(
                    value: Binding(get: { draft.bpm }, set: { draft.bpm = $0 }),
                    range: KotekanDraft.bpmRange,
                    suffix: "BPM"
                )
                AppMenuPicker(
                    options: Subdivision.denominators.map(Subdivision.init(denominator:)),
                    selection: Bindable(viewModel).snap,
                    title: \.label,
                    label: "Snap",
                    systemImage: "squareshape.split.3x3"
                )
            }

            divider

            if viewModel.recording { sensorSetup } else { PlayheadClock(viewModel: viewModel) }
            Spacer(minLength: 0)
        }
        .frame(height: 44)
    }

    /// The sensors' state, and which bilah they are taped to.
    private var sensorSetup: some View {
        let (text, color): (String, Color) = switch viewModel.sensor.status {
        case .off: ("Sensor off", Theme.stone)
        case .scanning: ("Searching…", Theme.gold)
        case .connecting: ("Connecting…", Theme.gold)
        case .connected: ("Connected", Theme.hit)
        case .locked: ("Needs its PIN", Theme.gold)
        case let .unavailable(why): (why, Theme.miss)
        }
        func range(_ first: Int) -> String {
            "\(first + 1)–\(first + viewModel.sensorCount)"
        }

        // The status is a coloured icon, its words only for VoiceOver: the bar
        // has no room for "Bluetooth permission denied", and green / gold /
        // red already says connected / still trying / not working.
        return HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.symbol(15, weight: .semibold))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: viewModel.sensor.status != .connected)
                .accessibilityLabel("Sensor: \(text)")

            if let link = viewModel.app.profile.controller {
                // Set up through the controller screen: every input already
                // knows its bilah, so there is nothing to place here.
                Text(link.name)
                    .font(.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Theme.cream.opacity(0.08), in: Capsule())
                    .accessibilityLabel("Recording from \(link.name)")
            } else {
                AppMenuPicker(
                    options: viewModel.sensorPlacements,
                    selection: Bindable(viewModel).firstSensorKey,
                    title: { "Bilah \(range($0))" },
                    label: "Sensors on"
                )
            }
        }
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

/// A typed number, e.g. the tempo. The − / + stepper it replaced gave its room
/// to the snap menu; typing makes 88 → 160 one entry, not seventy-two taps.
///
/// It writes through while the number is in range, so typing "1" on the way to
/// "120" does not set 1, and settles to the nearest allowed value when the
/// field is left.
struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String?

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            field
            if let suffix {
                Text(suffix).font(.sans(13)).foregroundStyle(Theme.stone)
            }
        }
        .foregroundStyle(Theme.cream)
        .fixedSize()
    }

    private var field: some View {
        TextField("", text: $text)
            .keyboardType(.numberPad)
            .focused($focused)
            .multilineTextAlignment(.center)
            .font(.sans(15, weight: .semibold))
            .frame(width: 52, height: 32)
            .background(Theme.deep.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Theme.buttonFill : Theme.cream.opacity(0.15), lineWidth: focused ? 2 : 1)
            )
            .onAppear { text = "\(value)" }
            .onChange(of: text) { _, new in
                let digits = String(new.filter(\.isNumber).prefix(3))
                if digits != new { text = digits }
                if let v = Int(digits), range.contains(v) { value = v }
            }
            .onChange(of: value) { _, v in
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

    private func commit() {
        value = (Int(text) ?? value).clamped(to: range.lowerBound, range.upperBound)
        text = "\(value)"
    }
}

/// Arms the sensors. Red, and filled while recording, so it is never a
/// question whether a hit on the gangsa is being written down.
///
/// Not an `AppButton`: its primary sets the label heavy and uppercase like
/// NEXT, so "Recording" jumped in weight and case. Like the half pills, only
/// the glass changes. Now icon-only (the label is dropped), so it's a circle.
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
        .accessibilityLabel(recording ? "Stop recording" : "Record from the sensors")
    }
}
