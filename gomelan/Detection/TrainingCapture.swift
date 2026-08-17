//
//  TrainingCapture.swift
//  gomelan
//
//  Harvests labelled key crops for retraining MalletDetector.
//
//  The whole point is that crops are produced by the SAME code path inference
//  uses — `CropMapper.bufferRect` then `MalletHitClassifier.crop`. Cropping by
//  hand in Photos cannot reproduce it, and the mismatch is invisible: Create ML
//  reports a happy number and the device disagrees, with nothing to point at.
//
//  Two properties come free from capturing in-app, and neither can be staged:
//
//   - ASPECT RATIO. The user chooses each key's rect during aligning, and the
//     model's square input is reached by SQUASHING, so how much a bar is
//     distorted depends on how the rect was drawn. Capturing through the real
//     path gathers the aspect ratios users actually produce.
//   - THE HARD NEGATIVES. A mallet hovering without striking, and a mallet on
//     the NEIGHBOURING bar clipping the edge of this crop, are the two cases the
//     current model gets wrong. Both are trivial to capture live and near
//     impossible to stage deliberately.
//
//  One strike labels every key at once: the struck bar is the positive, and the
//  other nine are negatives from the same frame, same lighting, same alignment.
//  That is a 10x return on each capture, and the negatives are exactly the ones
//  that matter, because the mallet really is in shot on the neighbours.
//
//  Output is a Create ML folder tree in Documents:
//
//      TrainingData/hit/strike_k03_a0.42_<t>.png
//      TrainingData/not-hit/neighbour_k04_a0.39_<t>.png
//
//  Create ML only reads the two class folders. The prefix and the key index are
//  there so a crop can be traced back, and so a category can be pulled out again
//  if it turns out to be doing harm.
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

nonisolated final class TrainingCapture {

    /// What the tapped/struck key is an example of. Everything else in the frame
    /// is a negative regardless.
    enum Intent: String, CaseIterable {
        /// Mallet in contact — the positive class.
        case strike
        /// Mallet above the bar but not striking. The most valuable negative:
        /// it is what a player does constantly and what the model most confuses.
        case hover
        /// Hand damping, no strike.
        case damp
        /// Nothing happening anywhere. No target key needed.
        case idle

        var label: String { self == .strike ? "hit" : "not-hit" }

        var title: String {
            switch self {
            case .strike: return "Strike"
            case .hover: return "Hover"
            case .damp: return "Damp"
            case .idle: return "Empty"
            }
        }
    }

    /// Per-category tallies, keyed by the filename prefix.
    private(set) var counts: [String: Int] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "gomelan.training.capture", qos: .utility)

    private let root: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("TrainingData", isDirectory: true)
        for label in ["hit", "not-hit"] {
            try? FileManager.default.createDirectory(
                at: root.appendingPathComponent(label, isDirectory: true),
                withIntermediateDirectories: true)
        }
        refreshCounts()
    }

    var rootURL: URL { root }

    /// Crop every key out of one frame and file it.
    ///
    /// `target` is the key the intent applies to; pass nil for `.idle`. Keys
    /// adjacent to the target are filed as `neighbour` rather than `empty`,
    /// because the mallet is genuinely in their crop — that is the distinction
    /// the model needs and the one a staged photo shoot never captures.
    func capture(frame: CGImage,
                 frameSize: CGSize,
                 keys: [InstrumentKey],
                 viewSize: CGSize,
                 target: Int?,
                 intent: Intent) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)

        // Crop on the calling side is cheap; only encoding and disk go async.
        var jobs: [(prefix: String, label: String, key: Int, aspect: Double, image: CGImage)] = []
        for key in keys {
            let rect = CropMapper.bufferRect(overlay: key.rect,
                                             bufferSize: frameSize,
                                             viewSize: viewSize)
            guard let crop = MalletHitClassifier.crop(frame, to: rect) else { continue }

            let isTarget = key.index == target
            let isNeighbour = target.map { abs($0 - key.index) == 1 } ?? false

            let prefix: String
            let label: String
            if isTarget {
                prefix = intent.rawValue
                label = intent.label
            } else if intent == .idle {
                // Deliberate empty-scene captures get their own prefix, distinct
                // from the incidental negatives below.
                //
                // Both are `not-hit` and the strike model cannot tell them apart,
                // which is fine — for THAT question they are the same thing. They
                // are not the same for any later question about hands. A crop
                // taken while the player was mid-figure very often contains the
                // damping hand on some other bar; a crop taken with nobody
                // touching the instrument never does. Filing them under one name
                // would make the clean set unrecoverable, and re-shooting it
                // costs a whole session.
                prefix = "idle"
                label = "not-hit"
            } else {
                prefix = isNeighbour ? "neighbour" : "empty"
                label = "not-hit"
            }

            let aspect = crop.height > 0 ? Double(crop.width) / Double(crop.height) : 0
            jobs.append((prefix, label, key.index, aspect, crop))
        }

        queue.async { [weak self] in
            guard let self else { return }
            for job in jobs {
                let name = String(format: "%@_k%02d_a%.2f_%d.png",
                                  job.prefix, job.key, job.aspect, stamp)
                let url = self.root
                    .appendingPathComponent(job.label, isDirectory: true)
                    .appendingPathComponent(name)
                if Self.writePNG(job.image, to: url) {
                    self.lock.lock()
                    self.counts[job.prefix, default: 0] += 1
                    self.lock.unlock()
                }
            }
        }
    }

    func snapshotCounts() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return counts
    }

    var total: Int { snapshotCounts().values.reduce(0, +) }

    /// Delete everything captured so far.
    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            for label in ["hit", "not-hit"] {
                let dir = self.root.appendingPathComponent(label, isDirectory: true)
                try? FileManager.default.removeItem(at: dir)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            self.lock.lock()
            self.counts.removeAll()
            self.lock.unlock()
        }
    }

    /// Recount from disk, so the tallies survive relaunching the app mid-session.
    private func refreshCounts() {
        var found: [String: Int] = [:]
        for label in ["hit", "not-hit"] {
            let dir = root.appendingPathComponent(label, isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for file in files {
                let prefix = file.split(separator: "_").first.map(String.init) ?? "?"
                found[prefix, default: 0] += 1
            }
        }
        lock.lock(); counts = found; lock.unlock()
    }

    /// Zip the whole tree and hand back a URL fit for a share sheet.
    ///
    /// `NSFileCoordinator` with `.forUploading` is the zip archiver already
    /// present on iOS — it hands back a temporary archive of a directory, which
    /// is exactly what is wanted and saves pulling in a compression library for
    /// one call. Runs on the capture queue behind the disk writes, so it can
    /// never race a capture that is still being flushed.
    func exportArchive(completion: @escaping (URL?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return DispatchQueue.main.async { completion(nil) } }
            var error: NSError?
            var result: URL?
            NSFileCoordinator().coordinate(readingItemAt: self.root,
                                           options: [.forUploading],
                                           error: &error) { zipped in
                // The coordinator's file is only valid inside this block, so it
                // has to be copied somewhere that outlives it.
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("gomelan-training.zip")
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.copyItem(at: zipped, to: destination)
                    result = destination
                } catch {
                    result = nil
                }
            }
            let out = result
            DispatchQueue.main.async { completion(out) }
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
