//
//  SampleRing.swift
//  gomelan
//
//  Fixed-size ring of raw mono samples, addressed by ABSOLUTE sample index since
//  the stream started. Absolute indexing is what lets onset times, fingerprint
//  windows and host timestamps all refer to the same timeline without any of
//  them holding a copy of the audio.
//
//  Preallocated: nothing here allocates once running, because it is written from
//  the audio thread.
//

import Foundation

final class SampleRing {

    private var storage: [Float]
    private let capacity: Int
    /// Total samples ever written — also the absolute index of the next write.
    private(set) var totalWritten: Int = 0

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = [Float](repeating: 0, count: capacity)
    }

    /// Oldest absolute index still held. Anything below this has been overwritten.
    var oldestAvailable: Int { max(0, totalWritten - capacity) }

    func reset() {
        totalWritten = 0
        for i in storage.indices { storage[i] = 0 }
    }

    func write(_ source: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        // A buffer larger than the ring can only leave its tail behind.
        let n = min(count, capacity)
        let skip = count - n
        var position = totalWritten % capacity

        var written = 0
        while written < n {
            let chunk = min(n - written, capacity - position)
            storage.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.advanced(by: position)
                    .update(from: source.advanced(by: skip + written), count: chunk)
            }
            position = (position + chunk) % capacity
            written += chunk
        }
        totalWritten += count
    }

    /// Whether `[from, from+count)` is entirely still in the ring.
    func contains(from: Int, count: Int) -> Bool {
        from >= oldestAvailable && from + count <= totalWritten
    }

    /// Copy `count` samples starting at absolute index `from`.
    /// Returns false and leaves `out` untouched if that range is unavailable.
    @discardableResult
    func read(from: Int, count: Int, into out: inout [Float]) -> Bool {
        guard contains(from: from, count: count) else { return false }
        if out.count != count { out = [Float](repeating: 0, count: count) }

        var position = from % capacity
        var read = 0
        out.withUnsafeMutableBufferPointer { dst in
            storage.withUnsafeBufferPointer { src in
                while read < count {
                    let chunk = min(count - read, capacity - position)
                    dst.baseAddress!.advanced(by: read)
                        .update(from: src.baseAddress!.advanced(by: position), count: chunk)
                    position = (position + chunk) % capacity
                    read += chunk
                }
            }
        }
        return true
    }
}
