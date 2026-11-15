//
//  CueMixer.swift
//  Kotek
//
//  The mixer behind CuePlayer's recorded samples: one `AVAudioSourceNode` that
//  sums every sounding sample itself, so a cut is a gain ramp applied per
//  sample on the render thread.
//
//  This replaced a pool of `AVAudioPlayerNode`s. A player node can only be
//  stopped dead, and stopping a ringing bass-heavy sample mid-waveform is a
//  step in the signal — a thump. The workaround, ramping `node.volume` from a
//  timer, moved the step to the timer's ticks: still audible as a zap, and the
//  main thread decides when they land. The pool also recycled nodes round
//  robin without asking whether they were idle, so a busy passage cut an 8 s
//  gong off after a few seconds to make room for a key.
//
//  Here nothing is ever stopped dead: a retrigger, a mute or a stop fades the
//  affected voices over `fadeSeconds`, sample-accurately, and a new strike
//  starts on a free slot while the old one dies away underneath it.
//
//  `nonisolated` on purpose: `render` runs on the audio thread. The main thread
//  talks to it only through a command queue behind an unfair lock, and the
//  render thread never waits for that lock — if it is contended it applies the
//  commands on the next block, a few ms later.
//

import AVFoundation
import os

final nonisolated class CueMixer: @unchecked Sendable {
    /// Which cues a fade or mute applies to.
    enum Group { case key, colotomic }

    static let fadeSeconds = 0.02
    /// A hand damping a ringing bilah: quick, but a choke rather than a cut —
    /// at `fadeSeconds` it clicked like a sample stopping, not bronze stopped.
    static let dampSeconds = 0.08
    private static let capacity = 48

    private enum Command {
        case play(AVAudioPCMBuffer, source: Int, group: Group, gainL: Float, gainR: Float)
        case fade(Group?)
        case damp(source: Int)
        case clear
    }

    /// Plain data on purpose: the render loop walks these without touching
    /// reference counts. `keepAlive` holds the buffers the pointers point into.
    private struct Voice {
        var active = false
        var samples: UnsafePointer<Float>
        var count = 0
        var position = 0
        var source = 0
        var group = Group.key
        var gainL: Float = 1
        var gainR: Float = 1
        var level: Float = 1
        /// Per-frame decrement of `level`; 0 while the voice is not fading.
        var fadeStep: Float = 0
    }

    let sampleRate: Double
    private let fadeStep: Float
    private let dampStep: Float
    private let slots: UnsafeMutablePointer<Voice>
    private var keepAlive = [AVAudioPCMBuffer?](repeating: nil, count: capacity)

    private let pending = OSAllocatedUnfairLock(initialState: [Command]())
    /// Render-thread side of the queue; swapped with `pending`, so the render
    /// thread appends and removes without allocating.
    private var scratch: [Command] = []

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        fadeStep = Float(1 / max(1, sampleRate * Self.fadeSeconds))
        dampStep = Float(1 / max(1, sampleRate * Self.dampSeconds))
        slots = .allocate(capacity: Self.capacity)
        let empty = Voice(samples: UnsafePointer(bitPattern: 1)!)
        slots.initialize(repeating: empty, count: Self.capacity)
        scratch.reserveCapacity(64)
        pending.withLock { $0.reserveCapacity(64) }
    }

    deinit {
        slots.deallocate()
    }

    /// The node to attach: stereo, at the mixer's rate.
    func makeNode() -> AVAudioSourceNode {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        return AVAudioSourceNode(format: format) { [self] _, _, frames, bufferList in
            let list = UnsafeMutableAudioBufferListPointer(bufferList)
            guard list.count >= 2,
                  let left = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = list[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            render(frames: Int(frames), left: left, right: right)
            return noErr
        }
    }

    // MARK: - Main thread

    /// Start `buffer` (mono, at `sampleRate`). Anything already sounding from
    /// the same `source` fades out under it.
    func play(_ buffer: AVAudioPCMBuffer, source: Int, group: Group, pan: Float = 0, volume: Float = 1) {
        // Linear balance: centre is unity on both sides, which is how loud the
        // pool of player nodes this replaced sounded.
        let left = volume * min(1, 1 - pan)
        let right = volume * min(1, 1 + pan)
        pending.withLock { $0.append(.play(buffer, source: source, group: group, gainL: left, gainR: right)) }
    }

    /// Fade out one group, or everything for nil.
    func fade(_ group: Group?) {
        pending.withLock { $0.append(.fade(group)) }
    }

    /// Stop whatever `source` is ringing, as a hand on the bilah would.
    func damp(source: Int) {
        pending.withLock { $0.append(.damp(source: source)) }
    }

    /// Drop every voice at once. Only for a stopped engine, where no audio is
    /// being rendered to click.
    func clear() {
        pending.withLock { $0.append(.clear) }
    }

    // MARK: - Render thread

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        applyPending()
        left.update(repeating: 0, count: frames)
        right.update(repeating: 0, count: frames)

        for s in 0 ..< Self.capacity where slots[s].active {
            var v = slots[s]
            let n = min(frames, v.count - v.position)
            var i = 0
            while i < n {
                let x = v.samples[v.position + i] * v.level
                left[i] += x * v.gainL
                right[i] += x * v.gainR
                i += 1
                if v.fadeStep > 0 {
                    v.level -= v.fadeStep
                    if v.level <= 0 { break }
                }
            }
            v.position += i
            if v.level <= 0 || v.position >= v.count {
                v.active = false
                keepAlive[s] = nil
            }
            slots[s] = v
        }
    }

    private func applyPending() {
        pending.withLockIfAvailable { swap(&scratch, &$0) }
        guard !scratch.isEmpty else { return }
        for command in scratch {
            switch command {
            case let .play(buffer, source, group, gainL, gainR):
                start(buffer, source: source, group: group, gainL: gainL, gainR: gainR)
            case let .fade(group):
                for s in 0 ..< Self.capacity where slots[s].active && (group == nil || slots[s].group == group) {
                    beginFade(s)
                }
            case let .damp(source):
                for s in 0 ..< Self.capacity where slots[s].active && slots[s].source == source {
                    beginFade(s, step: dampStep)
                }
            case .clear:
                for s in 0 ..< Self.capacity {
                    slots[s].active = false
                    keepAlive[s] = nil
                }
            }
        }
        scratch.removeAll(keepingCapacity: true)
    }

    private func beginFade(_ s: Int, step: Float? = nil) {
        if slots[s].fadeStep == 0 { slots[s].fadeStep = step ?? fadeStep }
    }

    private func start(_ buffer: AVAudioPCMBuffer, source: Int, group: Group, gainL: Float, gainR: Float) {
        guard let data = buffer.floatChannelData else { return }
        for s in 0 ..< Self.capacity where slots[s].active && slots[s].source == source {
            beginFade(s)
        }

        // A free slot, else the voice that is closest to gone. 48 slots against
        // fourteen sources means this only happens if something is wrong.
        var slot = -1
        var quietest: Float = .infinity
        for s in 0 ..< Self.capacity {
            if !slots[s].active { slot = s
                break
            }
            if slots[s].level < quietest { quietest = slots[s].level
                slot = s
            }
        }
        keepAlive[slot] = buffer
        slots[slot] = Voice(
            active: true,
            samples: UnsafePointer(data[0]),
            count: Int(buffer.frameLength),
            source: source,
            group: group,
            gainL: gainL,
            gainR: gainR
        )
    }
}
