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

import FoundationModels
import Observation
import os

@Generable
nonisolated struct SessionOverview {
    @Guide(description: "One or two sentences on how the session went: the overall accuracy, and which part of the gong cycle was strongest and which needs work.")
    var summary: String

    @Guide(description: "One or two sentences giving one specific way to practise the weakest part next time.")
    var suggestion: String
}

/// One book in the credit line, with the pages the overview was given from it.
///
/// "Given", not "used": the model is handed these passages and cannot say
/// reliably which of them it leaned on — a small model asked to cite tends to
/// cite whatever number it was shown. So the credit claims only what is true:
/// the advice was written with these pages in front of it.
struct BookCitation: Identifiable, Equatable {
    let book: BookInfo
    let pages: [Int]

    var id: String {
        book.title
    }

    /// "Michael Tenzer, Gamelan Gong Kebyar, pp. 213, 236"
    var label: String {
        let pageList = pages.map(String.init).joined(separator: ", ")
        let where_ = pages.count == 1 ? "p. \(pageList)" : "pp. \(pageList)"
        return [book.author, book.title, where_].compactMap { $0 }.joined(separator: ", ")
    }

    /// Grouped by book in the order the books first appear, pages ascending.
    static func from(_ passages: [BookPassage]) -> [BookCitation] {
        var order: [BookInfo] = []
        var pages: [BookInfo: Set<Int>] = [:]
        for p in passages {
            if pages[p.book] == nil { order.append(p.book) }
            pages[p.book, default: []].insert(p.page)
        }
        return order.map { BookCitation(book: $0, pages: pages[$0, default: []].sorted()) }
    }
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
    /// The books the advice drew on and the pages it was given from them,
    /// best match first. Empty when no book is bundled.
    private(set) var citations: [BookCitation] = []

    @ObservationIgnored private let log = Logger(subsystem: "Kotek", category: "overview")

    private static let instructions = """
        You are a patient Balinese gamelan teacher. A student has just practised \
        one half of a kotekan, an interlocking figure, on a gangsa, and you are \
        given the measured results of the session.
        Write in plain, encouraging English, speaking to the student as "you".
        Use only the numbers you are given and never change them.
        Base your advice on the teaching notes when they are relevant; otherwise \
        give general practice advice. Never mention the notes, a book or passages.
        """

    func run(facts: SessionFacts) async {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(.appleIntelligenceNotEnabled):
            phase = .notice("Turn on Apple Intelligence in Settings to get an overview of each session.")
            return
        case .unavailable(.modelNotReady):
            phase = .notice("The overview is still getting ready on this iPhone. Try again after your next session.")
            return
        case let .unavailable(reason):
            log.info("no overview: model unavailable (\(String(describing: reason)))")
            phase = .hidden
            return
        }

        phase = .thinking
        let passages = await BookIndex.bundled.passages(for: facts.query)
        citations = BookCitation.from(passages)
        log.debug("query: \(facts.query) → \(passages.map { "\($0.book.title) p\($0.page)" })")

        var prompt = "Session results:\n\(facts.text)\n"
        if !passages.isEmpty {
            prompt += "\nTeaching notes:\n"
            for (i, p) in passages.enumerated() {
                prompt += "[\(i + 1)] \(p.text)\n"
            }
        }
        prompt += "\nWrite the overview for the student."

        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            for try await snapshot in session.streamResponse(to: prompt, generating: SessionOverview.self) {
                summary = snapshot.content.summary ?? ""
                suggestion = snapshot.content.suggestion ?? ""
                if !summary.isEmpty { phase = .writing }
            }
            phase = summary.isEmpty ? .failed : .done
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
