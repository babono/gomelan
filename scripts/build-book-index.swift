#!/usr/bin/env swift
//
//  build-book-index.swift
//
//  Turns the teaching book (a PDF) into the vector index the results screen's
//  AI overview retrieves from: `Kotek/Resources/BookIndex.json`.
//
//      swift scripts/build-book-index.swift path/to/book.pdf "Book title" --pages 29-469
//
//  `--pages` keeps only the main text (PDF page numbers, not printed ones).
//  Worth setting: a glossary is dense with exactly the terms a query uses, so
//  left in, it wins every search with a definition instead of an explanation.
//
//  Run on a Mac, once per edition of the book. The app never sees the PDF —
//  only the passages and their vectors, so the PDF does not need to be in the
//  repo.
//
//  The vectors come from Apple's NaturalLanguage contextual embedding (a
//  BERT-style model shipped with the OS), averaged over a passage's tokens —
//  the same model and pooling the phone uses on the query. The index records
//  the model's identifier and the app loads exactly that model, so the two
//  sides are in the same vector space. A phone without it falls back to
//  keyword retrieval over the same passages (see `BookIndex`).
//
//  Not `NLEmbedding.sentenceEmbedding`, which was tried first: an iPhone 17
//  listed its revision as supported and had no model for it, and it knew
//  Balinese words so poorly that it ranked drum technique above kotekan.
//
//  Why not a vector database: a book is a couple of thousand passages.
//  Comparing a query against all of them is one dot product each, and a JSON
//  file in the bundle needs no server, no download and no account.
//

import Foundation
import NaturalLanguage
import PDFKit

var args = Array(CommandLine.arguments)
var pageRange: ClosedRange<Int>?
if let flag = args.firstIndex(of: "--pages"), flag + 1 < args.count {
    let bounds = args[flag + 1].split(separator: "-").compactMap { Int($0) }
    guard bounds.count == 2, bounds[0] <= bounds[1] else {
        print("--pages wants first-last, e.g. 29-469")
        exit(1)
    }
    pageRange = bounds[0] ... bounds[1]
    args.removeSubrange(flag ... flag + 1)
}
guard args.count >= 2 else {
    print("usage: swift scripts/build-book-index.swift book.pdf [\"Book title\"] [out.json] [--pages first-last]")
    exit(1)
}
let pdfURL = URL(fileURLWithPath: args[1])
let title = args.count >= 3 ? args[2] : pdfURL.deletingPathExtension().lastPathComponent
let outURL = URL(fileURLWithPath: args.count >= 4 ? args[3] : "Kotek/Resources/BookIndex.json")

guard let pdf = PDFDocument(url: pdfURL) else {
    print("could not open \(pdfURL.path)")
    exit(1)
}

// MARK: - Text, page by page

/// PDF text arrives as laid-out lines: words hyphenated across line ends,
/// hard breaks mid-sentence, runs of spaces from justified columns.
func clean(_ raw: String) -> String {
    raw.replacingOccurrences(of: "-\n", with: "")
        .replacingOccurrences(of: "\u{00AD}", with: "") // soft hyphen
        .components(separatedBy: .newlines).joined(separator: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}

struct Sentence {
    let page: Int
    let text: String
}

var sentences: [Sentence] = []
let tokenizer = NLTokenizer(unit: .sentence)
for i in 0 ..< pdf.pageCount {
    if let pageRange, !pageRange.contains(i + 1) { continue }
    guard let raw = pdf.page(at: i)?.string else { continue }
    let text = clean(raw)
    tokenizer.string = text
    tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
        let s = text[range].trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { sentences.append(Sentence(page: i + 1, text: s)) }
        return true
    }
}

// MARK: - Passages

/// About a paragraph each. Long enough to carry one idea whole, short enough
/// that three of them fit in the on-device model's context next to the
/// session's numbers — its window is 4,096 tokens in total.
let targetChars = 700

/// Contents pages, indexes and tables of figures are mostly numbers and dots;
/// they match every query a little and teach nothing.
func isProse(_ s: String) -> Bool {
    let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    return Double(letters) / Double(max(1, s.count)) > 0.6
}

struct Passage {
    let page: Int
    let text: String
}

var passages: [Passage] = []
var current: [Sentence] = []
func flush() {
    let text = current.map(\.text).joined(separator: " ")
    if text.count >= 120, isProse(text), let first = current.first {
        passages.append(Passage(page: first.page, text: text))
    }
}
for s in sentences {
    current.append(s)
    if current.map(\.text.count).reduce(0, +) >= targetChars {
        flush()
        // One sentence of overlap, so an idea split at a boundary is still
        // whole in one of the two passages.
        current = [current.last!]
    }
}
if current.count > 1 { flush() }

// MARK: - Vectors

let language = NLLanguage.english
guard let embedding = NLContextualEmbedding(language: language) else {
    print("no English contextual embedding on this Mac")
    exit(1)
}
try embedding.load()

/// The mean of the passage's token vectors, at unit length so the app's cosine
/// similarity is a plain dot product. Must match `BookIndex.embed` exactly —
/// a query pooled differently would land somewhere else in the space.
func embed(_ text: String) -> [Float]? {
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

/// Float32 in base64: a quarter the size of the same numbers as JSON text.
func encode(_ v: [Float]) -> String {
    v.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
}

struct Chunk: Encodable {
    let page: Int
    let text: String
    let vector: String
}

struct Index: Encodable {
    let title: String
    let language: String
    let model: String
    let dimension: Int
    let chunks: [Chunk]
}

var chunks: [Chunk] = []
for (n, p) in passages.enumerated() {
    guard let v = embed(p.text) else { continue }
    chunks.append(Chunk(page: p.page, text: p.text, vector: encode(v)))
    if n % 200 == 0 { print("embedded \(n) / \(passages.count)") }
}

let index = Index(
    title: title,
    language: language.rawValue,
    model: embedding.modelIdentifier,
    dimension: embedding.dimension,
    chunks: chunks
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
try encoder.encode(index).write(to: outURL)

let size = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
print("\(pdf.pageCount) pages → \(sentences.count) sentences → \(chunks.count) passages")
print("embedding \(embedding.modelIdentifier), \(embedding.dimension) dimensions")
print("wrote \(outURL.path) (\(size / 1024) KB)")
