//
//  VoiceCommandListener.swift
//  Kotek
//
//  The waterfall's ear for "slower", "pause", "polos". On-device dictation
//  (`SpeechAnalyzer`), English whatever the phone's language — the commands
//  are English words — fed from its own microphone engine, since this screen
//  has no strike detection running to share one with.
//
//  Results arrive as the whole utterance so far, again and again as it firms
//  up, so the same "slower" turns up several times; `handle` acts on it once.
//

import AVFoundation
import CoreMedia
import Observation
import Speech

@Observable
@MainActor
final class VoiceCommandListener {
    enum State: Equatable {
        case off
        case preparing
        case listening
        case unavailable(String)
    }

    private(set) var state = State.off
    var onCommand: ((VoiceCommand) -> Void)?

    private let mic = AVAudioEngine()
    private var tapped = false
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var startTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?

    /// The utterance (by where it starts) and the command last acted on.
    private var lastUtterance: CMTime?
    private var lastCommand: VoiceCommand?
    private var lastFiredAt: Double = 0

    // MARK: - Lifecycle

    func start() {
        switch state {
        case .off, .unavailable: break
        case .preparing, .listening: return
        }
        state = .preparing
        startTask = Task { await run() }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        stopMic()
        input?.finish()
        input = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        lastUtterance = nil
        lastCommand = nil
        state = .off
        // The session stays play-and-record. Putting `.playback` back from here
        // would race the next screen's own configuration — the next Learn step
        // turning voice on again, or detection's `.measurement` — and whichever
        // landed last would win.
    }

    private func run() async {
        guard await AudioSessionManager.requestRecordPermission() else {
            state = .unavailable("Microphone is off for Kotek in Settings")
            return
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            state = .unavailable("Voice commands aren't available on this device")
            return
        }
        // Dictation rather than `SpeechTranscriber`: it takes the command list
        // as contextual strings, and it runs on every device that has iOS 26.
        let transcriber = DictationTranscriber(
            locale: locale,
            // The phone is on a stand an arm's length away, with a gangsa between.
            contentHints: [.shortForm, .farField],
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .alternativeTranscriptions, .frequentFinalization],
            attributeOptions: []
        )
        do {
            // The English model, once per device; it may already be there.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            try Task.checkCancellation()

            await AudioSessionManager.configureForVoice()
            try Task.checkCancellation()

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let context = AnalysisContext()
            context.contextualStrings[.general] = VoiceCommand.vocabulary
            try await analyzer.setContext(context)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                state = .unavailable("Voice commands couldn't start")
                return
            }
            try await analyzer.prepareToAnalyze(in: format)
            try Task.checkCancellation()

            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            input = continuation
            self.analyzer = analyzer
            try startMic(converting: format, into: continuation)

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.handle(result)
                    }
                } catch {
                    print("[Voice] results ended: \(error)")
                }
            }
            try await analyzer.start(inputSequence: stream)
            observeConfigurationChanges()
            state = .listening
        } catch is CancellationError {
            // Stopped while starting; `stop` has already tidied up.
        } catch {
            print("[Voice] could not start: \(error)")
            stopMic()
            state = .unavailable("Voice commands couldn't start")
        }
    }

    // MARK: - Microphone

    private func startMic(converting format: AVAudioFormat, into continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let node = mic.inputNode
        let natural = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: natural, to: format) else {
            throw CocoaError(.featureUnsupported)
        }
        node.installTap(onBus: 0, bufferSize: 4096, format: natural, block: Self.tap(converter: converter, to: format, into: continuation))
        tapped = true
        mic.prepare()
        try mic.start()
    }

    private func stopMic() {
        if tapped {
            mic.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        mic.stop()
    }

    /// Built off the main actor: the tap runs on the audio thread, and a block
    /// made in here would inherit this class's isolation and trap there.
    private nonisolated static func tap(
        converter: AVAudioConverter,
        to format: AVAudioFormat,
        into continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let ratio = format.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed {
                    status.pointee = .noDataNow
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, out.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: out))
            }
        }
    }

    /// A route change (headphones, a call) stops the engine and may change the
    /// mic's format under the tap; start again from the top.
    private func observeConfigurationChanges() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: mic,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .listening else { return }
                self.stop()
                self.start()
            }
        }
    }

    // MARK: - Results

    private func handle(_ result: DictationTranscriber.Result) {
        let heard = [result.text] + result.alternatives
        guard let command = heard.lazy.compactMap({ VoiceCommand(heard: String($0.characters)) }).first else { return }
        let now = CACurrentMediaTime()
        // The same command again in the same utterance is that utterance
        // firming up, not a second command. The time check covers the moment
        // it is finalised and comes back under a slightly different start.
        let repeated = command == lastCommand && (result.range.start == lastUtterance || now - lastFiredAt < 1)
        lastUtterance = result.range.start
        guard !repeated else { return }
        lastCommand = command
        lastFiredAt = now
        onCommand?(command)
    }
}
