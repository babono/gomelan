#!/usr/bin/env swift
//
//  build-book-index.swift
//
//  Builds the vector index the results screen's AI overview retrieves from,
//  `Kotek/Resources/BookIndex.json`, one book at a time:
//
//      swift scripts/build-book-index.swift add book.pdf "Book title" [--pages 29-469] [--ocr]
//          [--spreads] [--author "Name"] [--url https://…] [--page-offset -27]
//      swift scripts/build-book-index.swift set "Book title" [--title …] [--author …] [--url …] [--page-offset …]
//      swift scripts/build-book-index.swift remove "Book title"
//      swift scripts/build-book-index.swift list
//
//  The overview cites the pages it drew on and links to `--url`, where to get
//  the book. `--page-offset` turns a PDF page into the number PRINTED on it,
//  which is what a reader can find: printed = PDF page + offset. A scan of
//  pages 5–210 starts at PDF page 1, so its offset is +4; a PDF with 27 pages
//  of cover and front matter has −27. `set` changes these without re-reading
//  the book.
//
//  `add` replaces a book already in the index under the same title, so
//  re-running it after a better scan is safe. Only the book being added needs
//  its PDF: the others stay as they are in the index.
//
//  `--pages` keeps only the main text (PDF page numbers, not printed ones).
//  Worth setting: a glossary is dense with exactly the terms a query uses, so
//  left in, it wins every search with a definition instead of an explanation.
//
//  `--pages` also takes a list, `4-48,50-83`, to drop a page photographed
//  twice.
//
//  `--spreads` is for a book photographed open, two printed pages to each PDF
//  page. Every page is read with text recognition, the lines are split into
//  the left and right page by where they sit, and each side's printed number
//  is read off its running header or footer instead of worked out from an
//  offset — such scans skip pages and slip in photo inserts, so the numbers
//  stop being a fixed distance from the PDF's. Passages then store the
//  printed page itself, and the offset is 0.
//
//  Scans work. A page with no text layer — a photo of a page, which is what
//  the iPhone's document scanner produces — is read with Apple's Vision text
//  recognition. `--ocr` forces that for every page, for PDFs whose text layer
//  exists but is poor (old library scans often have one).
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
//  Why not a vector database: a few books are a few thousand passages.
//  Comparing a query against all of them is one dot product each, and a JSON
//  file in the bundle needs no server, no download and no account.
//

import AppKit
import Foundation
import NaturalLanguage
import PDFKit
import Vision

// MARK: - Index file

struct StoredPassage: Codable {
    let page: Int
    let text: String
    /// Float32, little-endian, base64, unit length.
    let vector: String
}

struct Book: Codable {
    var title: String
    var author: String?
    /// Where to get the book — a publisher or bookshop page.
    var url: String?
    /// Printed page = PDF page + this. Passages store the PDF page, so a
    /// wrong offset is fixed with `set` instead of a re-scan. 0 for a book
    /// added with `--spreads`, whose passages store the printed page.
    var pageOffset: Int?
    let passages: [StoredPassage]
}

struct Index: Codable {
    let language: String
    let model: String
    let dimension: Int
    var books: [Book]
}

/// The one-book format this tool wrote before it took several, so an existing
/// index can be added to rather than rebuilt from PDFs nobody has to hand.
struct LegacyIndex: Decodable {
    let title: String
    let language: String
    let model: String
    let dimension: Int
    let chunks: [StoredPassage]
}

func fail(_ message: String) -> Never {
    print(message)
    exit(1)
}

func readIndex(_ url: URL) -> Index? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    if let index = try? JSONDecoder().decode(Index.self, from: data) { return index }
    if let old = try? JSONDecoder().decode(LegacyIndex.self, from: data) {
        return Index(language: old.language, model: old.model, dimension: old.dimension,
                     books: [Book(title: old.title, passages: old.chunks)])
    }
    fail("\(url.path) is not a book index")
}

func writeIndex(_ index: Index, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(index).write(to: url)
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("wrote \(url.path) (\(size / 1024) KB)")
}

func describe(_ index: Index) {
    for book in index.books {
        var line = "  \(book.title)"
        if let author = book.author { line += " (\(author))" }
        line += " — \(book.passages.count) passages"
        if let offset = book.pageOffset { line += ", page offset \(offset)" }
        print(line)
        if let url = book.url { print("    \(url)") }
    }
}

// MARK: - Arguments

var args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i ... i + 1)
    return value
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

let indexURL = URL(fileURLWithPath: option("--index") ?? "Kotek/Resources/BookIndex.json")
let pagesArg = option("--pages")
let spreads = flag("--spreads")
let forceOCR = flag("--ocr") || spreads
let newTitle = option("--title")
let author = option("--author")
let link = option("--url")
let offsetArg = option("--page-offset")
let pageOffset = offsetArg.flatMap { Int($0) }
if offsetArg != nil, pageOffset == nil { fail("--page-offset wants a whole number, e.g. -27") }
if spreads, pageOffset != nil { fail("--spreads reads the printed page numbers; it takes no --page-offset") }
if let link, URL(string: link)?.scheme?.hasPrefix("http") != true { fail("--url wants an http(s) link") }

let usage = """
    usage:
      swift scripts/build-book-index.swift add book.pdf "Book title" [--pages first-last[,first-last…]] [--ocr]
          [--spreads] [--author "Name"] [--url https://…] [--page-offset n]
      swift scripts/build-book-index.swift set "Book title" [--title …] [--author …] [--url …] [--page-offset n]
      swift scripts/build-book-index.swift remove "Book title"
      swift scripts/build-book-index.swift list
    """

switch args.first {
case "list":
    guard let index = readIndex(indexURL) else { fail("no index at \(indexURL.path)") }
    describe(index)
    exit(0)

case "remove":
    guard args.count == 2 else { fail(usage) }
    guard var index = readIndex(indexURL) else { fail("no index at \(indexURL.path)") }
    let before = index.books.count
    index.books.removeAll { $0.title == args[1] }
    guard index.books.count < before else { fail("no book titled \"\(args[1])\"") }
    try writeIndex(index, to: indexURL)
    describe(index)
    exit(0)

case "set":
    guard args.count == 2 else { fail(usage) }
    guard var index = readIndex(indexURL) else { fail("no index at \(indexURL.path)") }
    guard let i = index.books.firstIndex(where: { $0.title == args[1] }) else { fail("no book titled \"\(args[1])\"") }
    if let newTitle { index.books[i].title = newTitle }
    if let author { index.books[i].author = author }
    if let link { index.books[i].url = link }
    if let pageOffset { index.books[i].pageOffset = pageOffset }
    try writeIndex(index, to: indexURL)
    describe(index)
    exit(0)

case "add":
    guard args.count == 3 else { fail(usage) }

default:
    fail(usage)
}

let pdfURL = URL(fileURLWithPath: args[1])
let title = args[2]
var pageRanges: [ClosedRange<Int>]?
if let pagesArg {
    pageRanges = pagesArg.split(separator: ",").map { part in
        let bounds = part.split(separator: "-").compactMap { Int($0) }
        guard bounds.count == 2, bounds[0] <= bounds[1] else { fail("--pages wants first-last, e.g. 29-469 or 4-48,50-83") }
        return bounds[0] ... bounds[1]
    }
}

guard let pdf = PDFDocument(url: pdfURL) else { fail("could not open \(pdfURL.path)") }

// MARK: - Text recognition

/// Words Vision's language correction would otherwise "fix" into English —
/// left to itself it reads an unfamiliar "kotekan" as the nearest word it
/// knows. Only the terms a gamelan text leans on; not a dictionary.
let gamelanWords = [
    "gamelan", "gangsa", "kotekan", "polos", "sangsih", "kebyar", "pemade",
    "kantilan", "ugal", "reyong", "trompong", "jegogan", "calung", "penyacah",
    "kendang", "lanang", "wadon", "ceng-ceng", "kajar", "kempur", "kempli",
    "klentong", "gong", "bilah", "panggul", "ngubeng", "norot", "nyog", "cag",
    "ubit", "ubit-ubitan", "telu", "empat", "angsel", "pokok", "neliti",
    "gineman", "pengawak", "pengecet", "kawitan", "pengrangrang", "sekaha",
    "sekaa", "banjar", "pelegongan", "gong kebyar", "pengumbang", "pengisep",
]

/// The page drawn at three times its point size — about 216 dpi for a
/// letter-size page, enough for body text without slowing recognition down.
/// A photographed spread is already a large page; twice is plenty.
///
/// Upright, whatever the page's `/Rotate`: a phone scan can store every page
/// on its side, and Vision reads sideways text as nothing.
func render(_ page: PDFPage, scale: CGFloat = spreads ? 2 : 3) -> CGImage? {
    let box = page.bounds(for: .mediaBox)
    guard page.rotation % 360 == 0 else {
        // R `thumbnail` is the one PDFKit drawing call that turns the page
        // R upright; `draw(with:to:)` ignores `/Rotate`, and concatenating
        // R `transform(for:)` before it turned these pages the wrong way.
        let turned = page.rotation % 180 != 0
        let size = NSSize(width: (turned ? box.height : box.width) * scale,
                          height: (turned ? box.width : box.height) * scale)
        return page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    let width = Int(box.width * scale), height = Int(box.height * scale)
    guard width > 0, height > 0,
          let ctx = CGContext(
              data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
          )
    else { return nil }
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: ctx)
    return ctx.makeImage()
}

/// The page's text as Vision reads it, one recognised line per line.
///
/// ponytail: lines are kept in the order Vision returns them, which is
/// reading order for a single column. A two-column book would interleave its
/// columns; none of ours is one.
func recognise(_ page: PDFPage) -> String {
    recogniseLines(page).map(\.string).joined(separator: "\n")
}

/// Each recognised line with where it sits on the page (Vision's normalised
/// box, origin bottom left).
func recogniseLines(_ page: PDFPage) -> [(string: String, box: CGRect)] {
    guard let image = render(page) else { return [] }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US"]
    request.customWords = gamelanWords
    do {
        try VNImageRequestHandler(cgImage: image).perform([request])
    } catch {
        print("  page \(page.label ?? "?"): recognition failed, \(error.localizedDescription)")
        return []
    }
    return (request.results ?? []).compactMap { line in
        line.topCandidates(1).first.map { ($0.string, line.boundingBox) }
    }
}

/// One side of a spread: its lines top to bottom, and the number printed on
/// it, if its header or footer has one.
struct Side {
    let lines: [String]
    let number: Int?
}

/// A spread's lines split at the middle into the left and right page. By
/// line, not by cutting the image: a cut at the middle would slice through
/// any word near a gutter that is never quite centred.
func sides(_ page: PDFPage) -> [Side] {
    let lines = recogniseLines(page)
    return [true, false].map { left in
        var side = lines.filter { ($0.box.midX < 0.5) == left }
            .sorted { $0.box.maxY > $1.box.maxY }
            .map(\.string)
        let header = printedNumber(side)
        // R The running header is the same few words on every page; left in,
        // R it would be a little of every passage.
        if let header { side.remove(at: header.line) }
        return Side(lines: side, number: header?.number)
    }
}

/// "48 BALINESE GAMELAN MUSIC" or "BASIC PRINCIPLES OF GAMELAN MUSIC 49": a
/// number of up to three digits at either end of one of the first or last two
/// lines. A chapter opener or a photo has none.
func printedNumber(_ lines: [String]) -> (number: Int, line: Int)? {
    let edges = Array(lines.indices.prefix(2)) + lines.indices.suffix(2)
    for i in edges {
        let words = lines[i].split(separator: " ")
        for word in [words.first, words.last].compactMap({ $0 }) {
            if word.count <= 3, let n = Int(word), n > 0 { return (n, i) }
        }
    }
    return nil
}

/// The numbers read off each side in order, with the misreads dropped and the
/// gaps filled. A read is kept only if it climbs from the last kept one by no
/// more than the spreads between them hold (two pages each, counting any
/// left out with `--pages`), plus a few pages the scan skipped.
/// An unnumbered side is the next kept number counted back, or, where that
/// would not climb (a photo insert between numbered pages), the last kept
/// number again. Past the last number read, it counts on.
func resolvePageNumbers(_ read: [Int?], spreads sheet: [Int]) -> [Int] {
    var kept = [Int?](repeating: nil, count: read.count)
    var last: (at: Int, number: Int)?
    for (i, n) in read.enumerated() {
        guard let n else { continue }
        if let last, n <= last.number || n > last.number + 2 * (sheet[i] - sheet[last.at]) + 7 { continue }
        kept[i] = n
        last = (i, n)
    }
    var out = [Int](repeating: 0, count: read.count)
    var previous: (at: Int, number: Int)?
    for i in read.indices {
        if let n = kept[i] {
            out[i] = n
            previous = (i, n)
            continue
        }
        guard let next = kept[(i + 1)...].enumerated().first(where: { $0.element != nil }) else {
            out[i] = previous.map { $0.number + i - $0.at } ?? 1
            continue
        }
        let back = next.element! - (next.offset + 1)
        out[i] = back > (previous?.number ?? 0) ? back : previous?.number ?? 1
    }
    return out
}

/// A page with fewer characters than this in its text layer is treated as a
/// picture of a page. A real page of prose has well over a thousand.
let textLayerMinimum = 40

// MARK: - Text, page by page

/// Text arrives as laid-out lines: words hyphenated across line ends, hard
/// breaks mid-sentence, runs of spaces from justified columns.
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
var recognised = 0
let tokenizer = NLTokenizer(unit: .sentence)
func addSentences(_ text: String, page: Int) {
    tokenizer.string = text
    tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
        let s = text[range].trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { sentences.append(Sentence(page: page, text: s)) }
        return true
    }
}
let wantedPages = (0 ..< pdf.pageCount).filter { i in
    pageRanges.map { $0.contains { $0.contains(i + 1) } } ?? true
}

if spreads {
    var read: [(pdfPage: Int, side: Side)] = []
    for i in wantedPages {
        guard let page = pdf.page(at: i) else { continue }
        for side in sides(page) {
            read.append((i + 1, side))
        }
        recognised += 1
        if recognised % 10 == 0 { print("recognised \(recognised) spreads…") }
    }
    let numbers = resolvePageNumbers(read.map(\.side.number), spreads: read.map(\.pdfPage))
    // R Printed so a wrong number is caught here, not in a citation.
    for k in stride(from: 0, to: read.count, by: 2) {
        let marks = [k, k + 1].filter { $0 < read.count }
            .map { "\(numbers[$0])\(read[$0].side.number == nil ? "?" : "")" }
        print("  PDF \(read[k].pdfPage): \(marks.joined(separator: " | "))")
    }
    for (k, entry) in read.enumerated() {
        addSentences(clean(entry.side.lines.joined(separator: "\n")), page: numbers[k])
    }
}

for i in spreads ? [] : wantedPages {
    guard let page = pdf.page(at: i) else { continue }
    var raw = forceOCR ? "" : (page.string ?? "")
    if raw.trimmingCharacters(in: .whitespacesAndNewlines).count < textLayerMinimum {
        raw = recognise(page)
        recognised += 1
        if recognised % 25 == 0 { print("recognised \(recognised) pages…") }
    }
    addSentences(clean(raw), page: i + 1)
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
    fail("no English contextual embedding on this Mac")
}
try embedding.load()

var index = readIndex(indexURL)
    ?? Index(language: language.rawValue, model: embedding.modelIdentifier, dimension: embedding.dimension, books: [])
// R Every book in one index has to share one vector space. A new macOS can
// R ship a new model; mixing its vectors with the old ones would make every
// R comparison across books meaningless, silently.
guard index.model == embedding.modelIdentifier, index.dimension == embedding.dimension else {
    fail("""
        the index was built with embedding \(index.model) and this Mac has \(embedding.modelIdentifier).
        Remove the index and add every book again, so they share one model.
        """)
}

/// The mean of the passage's token vectors, at unit length so the app's cosine
/// similarity is a plain dot product. Must match `Semantic.embed` in
/// `BookIndex` exactly — a query pooled differently would land elsewhere.
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

var stored: [StoredPassage] = []
for (n, p) in passages.enumerated() {
    guard let v = embed(p.text) else { continue }
    stored.append(StoredPassage(page: p.page, text: p.text, vector: encode(v)))
    if n % 200 == 0 { print("embedded \(n) / \(passages.count)") }
}

// R A re-scan keeps the details given last time unless new ones are passed —
// R nobody should have to retype the link to fix one blurred page.
let previous = index.books.first { $0.title == title }
index.books.removeAll { $0.title == title }
index.books.append(Book(
    title: title,
    author: author ?? previous?.author,
    url: link ?? previous?.url,
    pageOffset: spreads ? 0 : pageOffset ?? previous?.pageOffset,
    passages: stored
))

print("\(title): \(pdf.pageCount) pages (\(recognised) read by text recognition) → \(sentences.count) sentences → \(stored.count) passages")
if previous != nil { print("replaced the earlier \"\(title)\"") }
try writeIndex(index, to: indexURL)
describe(index)
