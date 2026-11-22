//
//  ResultsView.swift
//  Kotek
//
//  The score, shown only when the player ends a session (PRD §4 Flow C, §8).
//  Practice loops indefinitely and never interrupts, so this is the one moment
//  the app says anything about how it went — encouraging tone with best stretch.
//
//  R One centred column now (the designer's results, November 2026): a
//  R headline, Kipli saying how it went, the numbers as tiles, the two ways on.
//  R The left half used to be a piano roll with the landed share drawn behind
//  R it and a minimap under it; it showed every slot, so the two or three that
//  R mattered had to be found. "See details" opens `PolishView`, which shows
//  R only those. A session with no sensor gets a result too — passes, time and
//  R top tempo — where it used to go straight back to the picker.
//

import SwiftUI
import Translation

struct ResultsView: View {
    @Environment(AppState.self) private var app
    @State private var overview = SessionOverviewModel()
    @State private var showingDetails = false

    var body: some View {
        if let result = app.lastResult {
            let spots = PolishSpot.spots(in: result)
            Group {
                if showingDetails, let k = app.selectedKotekan {
                    PolishView(
                        result: result,
                        kotekan: k,
                        half: app.chosenHalf,
                        spots: spots,
                        onBack: { showingDetails = false }
                    )
                } else {
                    summary(result, spots: spots)
                }
            }
            .overlay {
                if app.showingSavePrompt {
                    SaveProgressPrompt()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: app.showingSavePrompt)
            .task(id: result) {
                guard isScored(result) else { return }
                let started = Date.now.addingTimeInterval(-result.practiceSeconds - 60)
                let past = await app.pastSessions(before: started)
                await overview.run(facts: facts(result, past: past))
            }
            .translationTask(overview.translation) { session in
                await overview.translate(using: session)
            }
        } else {
            Color.clear.onAppear { app.backToKotekan() }
        }
    }

    private func summary(_ result: SongResult, spots: [PolishSpot]) -> some View {
        let says = kipliSays(result, spots: spots)
        return VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(headline(result))
                    .font(.serif(40))
                    .foregroundStyle(Theme.heading)
                Text(verbatim: subtitle(result))
                    .font(.sans(15))
                    .foregroundStyle(Theme.description)
            }
            KipliGuide(message: says.line, mood: says.mood)
                .frame(maxWidth: 560)

            HStack(spacing: 10) {
                ResultsStat(value: result.passes.formatted(), label: result.passes == 1 ? "cycle" : "cycles")
                ResultsStat(value: Self.played(result.practiceSeconds), label: "played")
                if isScored(result) {
                    ResultsStat(value: Theme.percentLabel(accuracy(result)), label: "accuracy")
                    if !spots.isEmpty {
                        AppButton(title: "See details", trailingSystemImage: "chevron.right", prominence: .quiet) {
                            showingDetails = true
                        }
                    }
                } else if let bpm = bpm(result.topTempoScale) {
                    ResultsStat(value: "\(bpm) BPM", label: "top tempo")
                }
            }

            ResultsBottomBar(
                onChooseAnother: { app.backToKotekan() },
                onRetry: { app.retry() }
            )
        }
        .padding(.horizontal, Theme.headerInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The headline number: the best stretch of passes, as `PracticeSession`
    /// files it, so "better than last time" compares like with like.
    private func accuracy(_ result: SongResult) -> Double {
        result.best?.accuracy ?? 0
    }

    /// A judged pass to score. A session the sensors heard but that ended
    /// before a pass came round is not scored either — there is nothing whole
    /// to measure.
    private func isScored(_ result: SongResult) -> Bool {
        result.sensed && result.best != nil
    }

    private func headline(_ result: SongResult) -> LocalizedStringKey {
        guard result.sensed else { return "Nice session!" }
        guard result.best != nil else { return "Not enough to score" }
        return switch accuracy(result) {
        case 0.9...: "That interlock is holding."
        case 0.6...: "Your hands are learning."
        case 0.4...: "A good start."
        default: "That one's tricky."
        }
    }

    /// What Kipli says. Scored, it is the AI overview once it is written, and
    /// a line from the top spot on a phone that cannot write one. Not streamed:
    /// the bubble types each new line out from the start, so streaming into it
    /// would restart it with every word.
    private func kipliSays(
        _ result: SongResult,
        spots: [PolishSpot]
    ) -> (line: LocalizedStringResource, mood: KipliGuide.Mood) {
        guard result.sensed else {
            return (
                "You played \(result.passes) cycles today. Add sensors next time and I can show you every hit.",
                .happy
            )
        }
        guard result.best != nil else {
            return ("Play one whole cycle with your sensors on and I can score it.", .happy)
        }
        let mood: KipliGuide.Mood = accuracy(result) < 0.4 ? .sad : .happy
        switch overview.phase {
        case .done:
            let said = [overview.summary, overview.suggestion].filter { !$0.isEmpty }.joined(separator: " ")
            return ("\(said)", mood)
        case .thinking, .writing:
            return ("Let me look back over your session…", mood)
        case .hidden, .failed, .notice:
            guard let top = spots.first else {
                return ("Clean all the way through. Try it a little faster next time.", mood)
            }
            return ("\(top.title). Tap See details and I'll show you where.", mood)
        }
    }

    /// "Ubitan Nyendok · Polos", and the tempo it ended at when it was scored.
    private func subtitle(_ result: SongResult) -> String {
        let name = app.selectedKotekan?.name ?? result.songTitle
        let parts = [name, app.chosenHalf.title]
        guard isScored(result), let bpm = bpm(app.tempoScale) else { return parts.joined(separator: " · ") }
        return (parts + ["\(bpm) BPM"]).joined(separator: " · ")
    }

    /// The figure's BPM, as the picker shows it, at a tempo scale.
    private func bpm(_ scale: Double) -> String? {
        app.selectedKotekan.map { Int((Double($0.bpm) * scale).rounded()).formatted() }
    }

    /// "4 min", "40 sec", "1 hr": the largest unit only.
    private static func played(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
        )
    }

    private func facts(_ result: SongResult, past: [PracticeHistoryRow]) -> SessionFacts {
        SessionFacts(
            result: result,
            past: past,
            figure: app.selectedKotekan?.name ?? result.songTitle,
            half: app.chosenHalf.title.lowercased(),
            tempo: Theme.tempoLabel(app.tempoScale)
        )
    }
}
