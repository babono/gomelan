//
//  SessionOverviewModel.swift
//  Kotek
//
//  The AI overview on the results screen: session facts → passages from the
//  teaching book → Apple's on-device model → two short paragraphs.
//
//  On-device on purpose. It is free, it works with no signal (practice rooms
//  and sanggar rarely have any), and nothing about anyone's playing leaves the
//  phone, so the App Store privacy answers do not change. The cost is a small
//  model on Apple Intelligence iPhones only; on any other phone the card is
//  simply not there.
//

import Foundation
import FoundationModels
import Observation
import os
import Translation

@Generable
nonisolated struct SessionOverview {
    @Guide(
        description: "At most 30 words, in one or two short sentences, said as the coach who listened (\"I heard…\"): whether this session was better, worse or about the same as the ones before (or that it is the first), then the one bilah to fix and where in the gong cycle."
    )
    var summary: String

    @Guide(
        description: "At most 25 words: one drill for next time, as an instruction that starts with a verb. Give the drill itself (how slow, how many times, what to listen for); do not repeat the problem from the summary."
    )
    var suggestion: String
}

@Observable
final class SessionOverviewModel {
    enum Phase: Equatable {
        /// No card at all: this iPhone cannot run the model.
        case hidden
        /// A line instead of an overview — Apple Intelligence is off, or the
        /// model is still downloading.
        case notice(String)
        /// Retrieving and waiting on the first words.
        case thinking
        case writing
        case done
        case failed
    }

    private(set) var phase: Phase = .thinking
    private(set) var summary = ""
    private(set) var suggestion = ""
    /// Set once an English overview is ready and the player reads another
    /// language the model cannot write (Indonesian, for now). The view runs
    /// it through `translate(using:)` — a `translationTask` is what lets the
    /// system offer the language download the first time.
    private(set) var translation: TranslationSession.Configuration?

    @ObservationIgnored private let log = Logger(subsystem: "Kotek", category: "overview")

    /// R Kipli's voice, not a teacher's report. The first prompt asked for "a
    /// R patient teacher" and got one: seven lines reciting every number on
    /// R the screen, then a closing motto. The rules below are the no-slop
    /// R list cut down to what a small model actually does wrong, plus a
    /// R coach's habits — where you stand against last time, then one
    /// R instruction, no menu of options. It opened with "you did X well" at
    /// R first; praise the numbers do not back reads as filler, so he compares
    /// R with your own past sessions instead. The numbers stay out because the tiles under him show them.
    private static let instructions = """
    You are Kipli, a barong who coaches a student learning Balinese gamelan. \
    The student just practised one half of a kotekan, an interlocking pattern, \
    on a gangsa. You watched the whole session, and you are given what was measured.

    How you talk:
    - Caring and patient. Open with how this session compares with the ones before \
    it: better, worse, or about the same, exactly as the results say. No praise \
    for its own sake. If it is worse, say so kindly and plainly; one session down \
    is part of learning. If it is the first, say you will be tracking from here.
    - Expressive, as if you were in the room: "I heard bilah 7 drag behind the beat."
    - Assertive, like a good coach: one clear instruction, never a list of options. \
    Say "Play", "Count", "Start"; never "you might consider" or "try to maybe".
    - Call the student "you" and yourself "I".
    - Short, plain sentences. Name the bilah and where in the gong cycle it happens. \
    Use at most one number; the screen already shows them. Never change or invent one.

    Never:
    - use these words: delve, foster, leverage, utilize, facilitate, empower, robust, \
    elevate, embark, harness, journey, testament, crucial, pivotal, truly, honestly, simply.
    - write "It's not X, it's Y", "Here's the thing", "Remember,", "Keep up the great work", \
    or end on a motto or a summary of what you just said.
    - use dashes, emoji, or exclamation marks in every sentence.
    - mention the teaching notes, a book or passages, or borrow their terms \
    (neliti, ombak, ngubeng…) unless the results use them too.

    Base your advice on the teaching notes when they fit; otherwise give general practice advice.
    """

    /// The app's language when the model cannot write it, so the English
    /// overview is translated on-device instead. nil when there is nothing to
    /// do: the app is in English, or the model writes the language itself.
    private static var translationTarget: Locale.Language? {
        guard let code = Bundle.main.preferredLocalizations.first, code != "en",
              !SystemLanguageModel.default.supportsLocale(Locale(identifier: code))
        else { return nil }
        return Locale.Language(identifier: code)
    }

    /// The app's own language when the model can write it, else English.
    ///
    /// The instructions, facts and teaching notes stay English — that is what
    /// the model reads best — and only the reply is asked for in the player's
    /// language. Named in English ("Indonesian") inside the English prompt.
    private static var replyLanguage: String {
        guard let code = Bundle.main.preferredLocalizations.first, code != "en",
              SystemLanguageModel.default.supportsLocale(Locale(identifier: code)),
              let name = Locale(identifier: "en").localizedString(forLanguageCode: code)
        else { return "English" }
        return name
    }

    /// The English overview into the player's language. If it can't be —
    /// the download was declined, or there is no signal to fetch it — the
    /// English stands: advice in the wrong language beats no advice.
    func translate(using session: TranslationSession) async {
        defer { phase = .done }
        do {
            let responses = try await session.translations(from: [
                .init(sourceText: summary, clientIdentifier: "summary"),
                .init(sourceText: suggestion, clientIdentifier: "suggestion")
            ])
            for r in responses {
                if r.clientIdentifier == "summary" { summary = r.targetText }
                if r.clientIdentifier == "suggestion" { suggestion = r.targetText }
            }
        } catch {
            log.error("overview translation failed: \(String(describing: error))")
        }
    }

    /// Dashes out, whatever the prompt said: a small model reaches for them as
    /// rhythm, and a speech bubble is short copy, where they read as slop.
    private static func tidy(_ text: String) -> String {
        text.replacing(/\s*[—–]\s*/, with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func run(facts: SessionFacts) async {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(.appleIntelligenceNotEnabled):
            phase =
                .notice(String(localized: "Turn on Apple Intelligence in Settings to get an overview of each session."))
            return
        case .unavailable(.modelNotReady):
            phase =
                .notice(
                    String(
                        localized: "The overview is still getting ready on this iPhone. Try again after your next session."
                    )
                )
            return
        case let .unavailable(reason):
            log.info("no overview: model unavailable (\(String(describing: reason)))")
            phase = .hidden
            return
        }

        phase = .thinking
        // R The pages are given to the model but no longer credited on
        // R screen: the overview is Kipli talking now, and a reading list in
        // R his speech bubble was the book talking.
        let passages = await BookIndex.bundled.passages(for: facts.query)
        log.debug("query: \(facts.query) → \(passages.map { "\($0.book.title) p\($0.page)" })")

        var prompt = "Session results:\n\(facts.text)\n"
        if !passages.isEmpty {
            prompt += "\nTeaching notes:\n"
            for (i, p) in passages.enumerated() {
                prompt += "[\(i + 1)] \(p.text)\n"
            }
        }
        prompt += "\nTalk to the student now, as Kipli."

        let session = LanguageModelSession(
            instructions: Self.instructions + "\nWrite in \(Self.replyLanguage)."
                // The app's own Indonesian voice: warm, and "kamu", never "Anda".
                + (Self.replyLanguage == "Indonesian" ? " Call the student \"kamu\"." : "")
        )
        do {
            let target = Self.translationTarget
            for try await snapshot in session.streamResponse(to: prompt, generating: SessionOverview.self) {
                summary = snapshot.content.summary ?? ""
                suggestion = snapshot.content.suggestion ?? ""
                // Not streamed when it is going to be translated: English
                // words flowing in, then swapped for Indonesian, reads as a glitch.
                if !summary.isEmpty, target == nil { phase = .writing }
            }
            summary = Self.tidy(summary)
            suggestion = Self.tidy(suggestion)
            if summary.isEmpty {
                phase = .failed
            } else if let target {
                translation = .init(source: Locale.Language(identifier: "en"), target: target)
            } else {
                phase = .done
            }
        } catch is CancellationError {
            // Left the results screen; nothing to show anyone.
        } catch {
            // R Guardrail trips, context overflows and unsupported locales all
            // R end the same way for the player: no overview this time. Not
            // R worth a different message each — none of them is something they
            // R can act on.
            log.error("overview failed: \(String(describing: error))")
            phase = .failed
        }
    }
}
