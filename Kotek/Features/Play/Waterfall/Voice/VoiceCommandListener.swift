//
//  VoiceCommandListener.swift
//  Kotek
//
//  The waterfall's ear for "slower", "pause", "polos". On-device dictation
//  (`SpeechAnalyzer`) in the app's language — "pelan", "jeda" when it is in
//  Indonesian — falling back to English where the device has no Indonesian
//  dictation. Fed from its own microphone engine, since this screen has no
//  strike detection running to share one with.
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
    /// What the transcript is matched in; settled when listening starts, so
    /// the hint can name the words that will actually work.
    private(set) var language = VoiceCommand.Language.english
    /// 0…1 while this device downloads the language's dictation model — the
    /// first time Indonesian is used, ~25 s on a good connection. nil otherwise.
    private(set) var downloadProgress: Double?
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
            state = .unavailable(String(localized: "Microphone is off for Kotek in Settings"))
            return
        }
        var language = VoiceCommand.Language.preferred
        var locale = await DictationTranscriber.supportedLocale(equivalentTo: language.locale)
        if locale == nil, language != .english {
            language = .english
            locale = await DictationTranscriber.supportedLocale(equivalentTo: language.locale)
        }
        guard var locale else {
            state = .unavailable(String(localized: "Voice commands aren't available on this device"))
            return
        }
        var transcriber = Self.transcriber(for: locale)
        do {
            do {
                try await install(transcriber)
            } catch where !(error is CancellationError) && language != .english {
                // R The Indonesian model is a download the English one usually
                // R isn't, and with no signal it sat on "Getting ready" for good.
                // R English is better than nothing; Indonesian is tried again
                // R the next time voice is turned on.
                print("[Voice] \(language) model unavailable, using English: \(error)")
                guard let english = await DictationTranscriber
                    .supportedLocale(equivalentTo: VoiceCommand.Language.english.locale)
                else { throw error }
                language = .english
                locale = english
                transcriber = Self.transcriber(for: locale)
                try await install(transcriber)
            }
            self.language = language
            try Task.checkCancellation()

            await AudioSessionManager.configureForVoice()
            try Task.checkCancellation()

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let context = AnalysisContext()
            context.contextualStrings[.general] = VoiceCommand.vocabulary(language)
            try await analyzer.setContext(context)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                state = .unavailable(String(localized: "Voice commands couldn't start"))
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
            state = .unavailable(String(localized: "Voice commands couldn't start"))
        }
    }

    /// Dictation rather than `SpeechTranscriber`: it takes the command list
    /// as contextual strings, and it runs on every device that has iOS 26.
    private static func transcriber(for locale: Locale) -> DictationTranscriber {
        DictationTranscriber(
            locale: locale,
            // The phone is on a stand an arm's length away, with a gangsa between.
            contentHints: [.shortForm, .farField],
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .alternativeTranscriptions, .frequentFinalization],
            attributeOptions: []
        )
    }

    private struct DownloadStalled: Error {}

    /// The language's model, once per device; it may already be there. The
    /// progress is shown, and a download that stops moving for `stallLimit`
    /// seconds is given up on rather than waited out.
    private func install(_ transcriber: DictationTranscriber) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        let stallLimit = 45.0
        downloadProgress = 0
        defer { downloadProgress = nil }
        let download = Task { try await request.downloadAndInstall() }
        do {
            var last = -1.0
            var movedAt = CACurrentMediaTime()
            while !request.progress.isFinished {
                try await Task.sleep(for: .milliseconds(500))
                let progress = request.progress.fractionCompleted
                downloadProgress = progress
                if progress != last {
                    last = progress
                    movedAt = CACurrentMediaTime()
                } else if CACurrentMediaTime() - movedAt > stallLimit {
                    throw DownloadStalled()
                }
            }
            try await download.value
        } catch {
            download.cancel()
            throw error
        }
    }

    // MARK: - Microphone

    private func startMic(
        converting format: AVAudioFormat,
        into continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let node = mic.inputNode
        let natural = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: natural, to: format) else {
            throw CocoaError(.featureUnsupported)
        }
        node.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: natural,
            block: Self.tap(converter: converter, to: format, into: continuation)
        )
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
        let language = language
        guard let command = heard.lazy.compactMap({ VoiceCommand(heard: String($0.characters), in: language) }).first
        else { return }
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
