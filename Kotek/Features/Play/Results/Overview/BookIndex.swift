//
//  BookIndex.swift
//  Kotek
//
//  The retrieval half of the AI overview: given a question about a session,
//  find the passages of the teaching book that speak to it.
//
//  The book is indexed on a Mac by `scripts/build-book-index.swift` into
//  `Resources/BookIndex.json` — passages plus one vector each, from Apple's
//  contextual embedding. Here the query is embedded with the same model and
//  compared against every passage. No vector database: a book is a couple of
//  thousand passages, and a dot product against each takes well under a
//  millisecond.
//
//  Hybrid, not vectors alone. The embedding barely knows Balinese words — to
//  it "kotekan", "polos" and "sangsih" are fragments — so on its own it
//  surfaced passages about shadow play and drum technique. A keyword score
//  (BM25) over the same passages rewards actually using the query's terms,
//  and the two together found the chapter on kotekan for every query tried.
//
//  An actor because loading megabytes of JSON and running the embedding are
//  both work the results screen must not wait on.
//

import Accelerate
import Foundation
import NaturalLanguage
import os

nonisolated struct BookPassage: Sendable, Equatable {
    let book: BookInfo
    /// The number printed on the page, which is what a reader can turn to —
    /// not the PDF's page, which counts the cover and front matter too.
    let page: Int
    let text: String
}

/// A book as the overview credits it.
nonisolated struct BookInfo: Sendable, Hashable {
    let title: String
    let author: String?
    /// Where to get it — a publisher or bookshop page.
    let url: URL?
}

actor BookIndex {
    /// ponytail: one book, loaded on first use and kept for the launch. A
    /// second book would make this a parameter, not a second singleton.
    static let bundled = BookIndex(resource: "BookIndex")

    private let resource: String
    private var loaded: Loaded?
    /// Set once loading has failed, so a missing or broken index costs one
    /// attempt per launch rather than one per session.
    private var unavailable = false

    private let log = Logger(subsystem: "Kotek", category: "overview")

    init(resource: String) {
        self.resource = resource
    }

    /// The `count` passages closest to `query`, best first. Empty when no book
    /// is bundled — the overview is then written from the session alone,
    /// which is worse but not wrong.
    func passages(for query: String, count: Int = 3) async -> [BookPassage] {
        guard let index = await load() else { return [] }
        let keywords = Self.scaled(index.keywords.scores(for: Set(Keywords.words(in: query))))
        // R Without the model (see `read`), keywords alone — still the right
        // R chapter, just less often the right paragraph of it.
        let cosine = index.semantic?.similarities(to: query).map(Self.scaled)

        // R Both scaled to 0–1 across the book and weighted equally. Cosine and
        // R BM25 live on unrelated scales, and adding them raw let whichever
        // R had the wider spread decide alone. Tuned by hand on the kebyar book.
        let scored = keywords.indices.map { i in
            (0.5 * keywords[i] + 0.5 * (cosine?[i] ?? 0), i)
        }
        return scored
            .filter { $0.0 > 0 }
            .sorted { $0.0 > $1.0 }
            .prefix(count)
            .map { index.passages[$0.1] }
    }

    // MARK: - Loading

    /// Every book's passages in one list. One corpus rather than one per book:
    /// the question is which passages answer the query, wherever they are, and
    /// keyword rarity and the vectors' mean are both measured across all of it.
    private struct Loaded {
        let passages: [BookPassage]
        /// Nil when this phone does not have the index's embedding model.
        let semantic: Semantic?
        let keywords: Keywords
    }

    nonisolated private struct File: Decodable {
        let language: String
        /// The `NLContextualEmbedding` every book's vectors came from — the
        /// builder refuses to mix models in one index.
        let model: String
        let dimension: Int
        let books: [Book]

        nonisolated struct Book: Decodable {
            let title: String
            let author: String?
            let url: String?
            /// Printed page = PDF page + this.
            let pageOffset: Int?
            let passages: [Passage]
        }

        nonisolated struct Passage: Decodable {
            let page: Int
            let text: String
            /// Float32, little-endian, base64.
            let vector: String
        }
    }

    private func load() async -> Loaded? {
        if let loaded { return loaded }
        guard !unavailable else { return nil }
        loaded = await read()
        unavailable = loaded == nil
        return loaded
    }

    private func read() async -> Loaded? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else { return nil }
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        } catch {
            log.error("book index unreadable: \(String(describing: error))")
            return nil
        }
        let stored = file.books.flatMap { book in
            let info = BookInfo(title: book.title, author: book.author, url: book.url.flatMap(URL.init(string:)))
            return book.passages.map { (info, $0.page + (book.pageOffset ?? 0), $0) }
        }
        let passages = stored.map { BookPassage(book: $0.0, page: $0.1, text: $0.2.text) }
        let vectors = stored.map { Self.floats(base64: $0.2.vector, count: file.dimension) }
        guard !passages.isEmpty, vectors.allSatisfy({ $0.count == file.dimension }) else { return nil }

        return Loaded(
            passages: passages,
            semantic: await semantic(file: file, vectors: vectors),
            keywords: Keywords(passages.map(\.text))
        )
    }

    /// The exact model the book was indexed with — vectors from two models are
    /// not comparable at all, not slightly off but unrelated — or nil.
    private func semantic(file: File, vectors: [[Float]]) async -> Semantic? {
        let language = NLLanguage(file.language)
        guard let embedding = NLContextualEmbedding(modelIdentifier: file.model) else {
            log.info("embedding \(file.model) not on this OS; keyword retrieval only")
            return nil
        }
        // R Asked for, AWAITED, then loaded — every step of that is load-bearing.
        // R On an iPhone 17 `hasAvailableAssets` said false on every launch,
        // R `load()` alone failed with "Failed to locate embedding model", and a
        // R fire-and-forget request came back "available" without changing
        // R either. Awaiting the request first is what made the model load,
        // R and when the assets are already there it returns in milliseconds.
        do {
            guard try await embedding.requestAssets() == .available else {
                log.info("embedding assets not available yet; keyword retrieval")
                return nil
            }
            try embedding.load()
        } catch {
            log.info("embedding not loadable (\(String(describing: error))); keyword retrieval")
            return nil
        }
        log.info("embedding \(file.model) loaded; hybrid retrieval")
        return Semantic(embedding: embedding, language: language, vectors: vectors)
    }

    private static func floats(base64: String, count: Int) -> [Float] {
        guard let data = Data(base64Encoded: base64), data.count == count * MemoryLayout<Float>.size
        else { return [] }
        // R Copied rather than rebound: a Data's bytes carry no alignment
        // R promise, and reading Floats through a misaligned pointer traps.
        var out = [Float](repeating: 0, count: count)
        _ = out.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return out
    }

    /// Min–max to 0…1, so two unrelated scores can be mixed by weight.
    private static func scaled(_ xs: [Double]) -> [Double] {
        guard let lo = xs.min(), let hi = xs.max(), hi > lo else { return xs.map { _ in 0 } }
        return xs.map { ($0 - lo) / (hi - lo) }
    }
}

/// Vector similarity against the book.
nonisolated private struct Semantic {
    let embedding: NLContextualEmbedding
    let language: NLLanguage
    /// The book's average vector, taken off every vector before comparing.
    ///
    /// Averaged token vectors from a BERT-style model all lean the same way:
    /// across this book every passage scored 0.69–0.93 against every query, so
    /// cosine barely ranked anything. Centring on the book's own mean removes
    /// the shared lean, and the same queries then spread from −0.5 to 0.5.
    let mean: [Float]
    /// Centred and unit length, so cosine similarity is a plain dot product.
    let vectors: [[Float]]

    init(embedding: NLContextualEmbedding, language: NLLanguage, vectors raw: [[Float]]) {
        self.embedding = embedding
        self.language = language
        var mean = [Float](repeating: 0, count: embedding.dimension)
        for v in raw {
            vDSP_vadd(mean, 1, v, 1, &mean, 1, vDSP_Length(mean.count))
        }
        var scale = 1 / Float(max(1, raw.count))
        vDSP_vsmul(mean, 1, &scale, &mean, 1, vDSP_Length(mean.count))
        self.mean = mean
        vectors = raw.map { Semantic.centred($0, on: mean) }
    }

    /// Cosine similarity of every passage to `text`, or nil if the model
    /// cannot read it.
    func similarities(to text: String) -> [Double]? {
        guard let q = embed(text), q.count == mean.count else { return nil }
        let query = Semantic.centred(q, on: mean)
        return vectors.map { v in
            var dot: Float = 0
            vDSP_dotpr(query, 1, v, 1, &dot, vDSP_Length(query.count))
            return Double(dot)
        }
    }

    /// The mean of the text's token vectors, at unit length. Must match
    /// `embed` in `scripts/build-book-index.swift` exactly: a query pooled
    /// differently from the passages lands somewhere else in the space.
    private func embed(_ text: String) -> [Float]? {
        guard let result = try? embedding.embeddingResult(for: text, language: language) else { return nil }
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex ..< text.endIndex) { vector, _ in
            for i in sum.indices { sum[i] += vector[i] }
            count += 1
            return true
        }
        guard count > 0 else { return nil }
        let norm = sqrt(sum.reduce(0) { $0 + $1 * $1 })
        return sum.map { Float($0 / max(norm, 1e-12)) }
    }

    private static func centred(_ v: [Float], on mean: [Float]) -> [Float] {
        var c = [Float](repeating: 0, count: v.count)
        vDSP_vsub(mean, 1, v, 1, &c, 1, vDSP_Length(v.count))
        var norm: Float = 0
        vDSP_svesq(c, 1, &norm, vDSP_Length(c.count))
        norm = sqrt(norm)
        guard norm > 0 else { return c }
        return c.map { $0 / norm }
    }
}

/// BM25 over the passages: how strongly each one uses the query's words,
/// with rare words counting for more than common ones.
nonisolated private struct Keywords {
    private let documents: [[String: Int]]
    private let lengths: [Int]
    private let documentFrequency: [String: Int]
    private let averageLength: Double

    init(_ texts: [String]) {
        documents = texts.map { text in
            Keywords.words(in: text).reduce(into: [:]) { $0[$1, default: 0] += 1 }
        }
        lengths = documents.map { $0.values.reduce(0, +) }
        documentFrequency = documents.reduce(into: [:]) { df, doc in
            for w in doc.keys { df[w, default: 0] += 1 }
        }
        averageLength = Double(lengths.reduce(0, +)) / Double(max(1, lengths.count))
    }

    /// Lowercased words of three letters or more. Shorter ones are nearly all
    /// "of", "in", "on" — IDF would discount them anyway.
    static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 }
    }

    func scores(for query: Set<String>) -> [Double] {
        let n = Double(documents.count)
        let idf = query.reduce(into: [String: Double]()) { idf, w in
            guard let df = documentFrequency[w] else { return }
            idf[w] = log(1 + (n - Double(df) + 0.5) / (Double(df) + 0.5))
        }
        // The textbook constants, k1 = 1.2 and b = 0.75.
        return documents.indices.map { i in
            let norm = 1.2 * (0.25 + 0.75 * Double(lengths[i]) / max(1, averageLength))
            return idf.reduce(0) { total, term in
                guard let tf = documents[i][term.key] else { return total }
                return total + term.value * Double(tf) * 2.2 / (Double(tf) + norm)
            }
        }
    }
}
