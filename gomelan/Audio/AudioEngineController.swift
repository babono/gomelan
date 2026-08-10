//
//  AudioEngineController.swift
//  gomelan
//
//  Ties the live mic to the detection pipeline (PRD §6.3):
//
//    mic tap → sliding FFT window → spectral-flux onset → key classifier → strike
//
//  Emits (keyIndex, hostTime, confidence) on the main queue. hostTime uses the
//  same CACurrentMediaTime() clock the PlayEngine judges against.
//

import AVFoundation
import QuartzCore

final class AudioEngineController {

    /// Called on the main queue for each detected strike.
    var onStrike: ((_ keyIndex: Int, _ hostTime: Double, _ confidence: Double) -> Void)?

    /// Called on the main queue for each onset with the raw estimated
    /// fundamental, before any key matching. Used by the calibration flow to
    /// record the instrument's own pitches.
    var onRawOnset: ((_ fundamentalHz: Double, _ hostTime: Double) -> Void)?

    private let engine = AVAudioEngine()
    private let fftSize = 4096          // §6.3 validated window
    private let hop = 1024
    private lazy var fft = FFTProcessor(size: fftSize)
    private let onset = OnsetDetector()
    private var classifier: KeyClassifier?

    private let lock = NSLock()
    private var accumulator: [Float] = []
    private var sampleClock: Int = 0
    private var sampleRate: Double = 44100
    private(set) var isRunning = false

    func start(profile: InstrumentProfile) throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 44100

        classifier = KeyClassifier(fft: fft, sampleRate: sampleRate, keys: profile.keys)
        lock.withLock {
            onset.reset()
            accumulator.removeAll(keepingCapacity: true)
            accumulator.reserveCapacity(fftSize * 2)
            sampleClock = 0
        }

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            self?.handleTap(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    func resetDetector() {
        lock.withLock {
            onset.reset()
            accumulator.removeAll(keepingCapacity: true)
        }
    }

    func updateKeys(_ keys: [InstrumentKey]) {
        classifier?.updateKeys(keys)
    }

    // MARK: - Processing (audio thread)

    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)

        lock.withLock {
            accumulator.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))

            while accumulator.count >= fftSize {
                let window = Array(accumulator[0..<fftSize])
                let spectrum = fft.magnitudeSpectrum(window)
                let time = Double(sampleClock) / sampleRate

                if onset.process(spectrum: spectrum, time: time) {
                    if let hz = classifier?.fundamental(spectrum: spectrum) {
                        DispatchQueue.main.async { [weak self] in
                            self?.onRawOnset?(hz, CACurrentMediaTime())
                        }
                    }
                    if let match = classifier?.classify(spectrum: spectrum) {
                        let idx = match.keyIndex
                        let conf = match.confidence
                        DispatchQueue.main.async { [weak self] in
                            self?.onStrike?(idx, CACurrentMediaTime(), conf)
                        }
                    }
                }

                if accumulator.count >= hop {
                    accumulator.removeFirst(hop)
                    sampleClock += hop
                } else {
                    accumulator.removeAll(keepingCapacity: true)
                }
            }
        }
    }
}
