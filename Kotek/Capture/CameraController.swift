//
//  CameraController.swift
//  Kotek
//
//  AVCaptureSession around the back wide camera (PRD §6.2). Focus and exposure
//  are locked after framing so autofocus hunting doesn't drift the overlay off
//  the keys.
//
//  Not main-actor isolated: the capture session is configured and driven on a
//  dedicated serial queue. Observable state is published back to the main queue.
//

import AVFoundation
import Observation

@Observable
final class CameraController: NSObject {
    enum Status: Equatable {
        case idle
        case configuring
        case running
        case denied
        case failed(String)
    }

    private(set) var status: Status = .idle

    /// Exposed for the preview layer.
    @ObservationIgnored let session = AVCaptureSession()

    /// THE preview layer — one for the whole app, not one per screen.
    ///
    /// Every camera screen used to build its own via `layerClass` and assign
    /// `.session` to it. Assigning a session to a preview layer ADDS A
    /// CONNECTION, and doing that to an already-running session makes it
    /// renegotiate: measured at 9007ms on the way from the demo screen into a
    /// run, on the main thread, which was the entire reported delay.
    ///
    /// One layer means that cost is paid once, during preload, while the
    /// session is still stopped — and a screen change afterwards is a CALayer
    /// being re-parented, which is free. `addSublayer` detaches it from its
    /// previous view automatically, so the layer simply follows whichever
    /// preview is on screen.
    ///
    /// Created lazily rather than eagerly: on a first launch, before camera
    /// permission exists, there is no session worth attaching to yet.
    @ObservationIgnored lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        layer.session = session
        return layer
    }()

    /// Short rolling history of frames, keyed by host time, for vision fusion
    /// (StrikeFusion looks up the frame nearest an audio strike).
    @ObservationIgnored let frameBuffer = FrameBuffer()

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "me.babono.kotek.camera.session")

    /// Frame delivery, on its OWN queue — never `sessionQueue`.
    ///
    /// These were the same queue, and that is what made entering a run take
    /// nine seconds. Every delivered frame is rendered to a CGImage by
    /// `FrameBuffer.ingest`, which is CoreImage work at 30fps; sharing the
    /// session's queue meant configuring the session — including attaching a
    /// new preview layer, which is what a screen change does — had to wait
    /// behind that. Measured at 9040ms before `PlayView` had even appeared.
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "me.babono.kotek.camera.video",
                                                              qos: .userInitiated)

    /// Whether delivered frames are rendered into `frameBuffer`.
    ///
    /// Only the screens that actually classify crops need them — play, the
    /// aligning fit, the mallet/detection tests. The demo screen shows a live
    /// preview and detects nothing, so rendering a CGImage per frame there is
    /// pure cost: battery, heat, and a queue busy at exactly the moment the
    /// player taps through to the run.
    ///
    /// Defaults to TRUE so that a screen which forgets to ask still works. It
    /// is opted OUT of explicitly, which fails safe: the worst case is wasted
    /// work rather than a detector that silently sees nothing.
    @ObservationIgnored var wantsFrames = true
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var videoOutput: AVCaptureVideoDataOutput?
    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var lastRotationAngle: CGFloat = -1

    // MARK: - Permissions

    static var cameraAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard status != .running else { return }
        setStatus(.configuring)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
            self.setStatus(.running)
        }
    }

    /// Build the capture graph without switching the camera on.
    ///
    /// Called from the splash screen. `configureIfNeeded()` is the slow half of
    /// opening the camera — finding the device, building the input, negotiating
    /// the output format, committing the configuration — and it is identical
    /// every launch, so there is no reason for the framing screen to pay for it
    /// while the player is looking at a black rectangle. A later `start()` then
    /// only has `startRunning()` left to do.
    ///
    /// Deliberately stops short of `startRunning()`. Running the session lights
    /// the system recording indicator and keeps the sensor powered, and the
    /// splash and welcome screens show no preview at all — the app should not
    /// look like it is watching when there is nothing to watch. Status is left
    /// alone for the same reason: nothing is running yet, and claiming otherwise
    /// would make `start()` return early and never actually open the camera.
    func prepare() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.configureIfNeeded()
                continuation.resume()
            }
        }
        // Build and attach the preview layer HERE, while the session is
        // configured but not yet running. Attaching to a running session is the
        // expensive case — nine seconds of it — and this is the one moment the
        // app is guaranteed to have a configured, stopped session and time to
        // spare. Cheap and pointless-looking; it is neither.
        _ = previewLayer
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.setStatus(.idle)
        }
    }

    // MARK: - Focus / exposure lock (§6.2)

    /// Lock focus and exposure once the instrument is framed, so key positions
    /// don't shift between frames.
    func lockFocusAndExposure() {
        sessionQueue.async { [weak self] in
            self?.applyLock()
        }
    }

    /// Awaitable form, for callers that want to hold a "saving…" state until the
    /// lens has actually settled rather than change screen out from under it.
    func lockFocusAndExposureAsync() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.applyLock()
                continuation.resume()
            }
        }
    }

    private func applyLock() {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            //R Exposure is marker mode's to own while it is on. Both this and
            //R `enableContinuousAutoFocus` are called from screen setup, AFTER
            //R the toggle has already configured the device — so without the
            //R guard, entering the detection screen in marker mode handed the
            //R exposure straight back to autoexposure and the marker stopped
            //R being the only bright thing in the frame.
            if !markerVisionActive, device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            device.unlockForConfiguration()
        } catch {
            // Non-fatal: some devices won't allow locking; overlay still works.
        }
    }

    /// Undo a previous lock and let the camera focus/expose continuously again.
    ///
    /// The device is shared hardware: once `lockFocusAndExposure()` runs (in the
    /// aligning flow) the lock persists across every screen that reuses this
    /// controller, so a later screen shows a frozen — often blurry — image until
    /// focus is handed back. Screens that don't need a frozen overlay call this.
    func enableContinuousAutoFocus() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if !self.markerVisionActive, device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
                device.unlockForConfiguration()
            } catch {
                // Non-fatal: leave whatever mode the device is already in.
            }
        }
    }

    // MARK: - Marker vision (torch + shortened exposure)

    /// Whether the device is currently held in the marker exposure. Touched only
    /// on `sessionQueue`, which is also the only place the lock/unlock paths run.
    private var markerVisionActive = false

    /// Light the scene from beside the lens and expose for the marker instead of
    /// for the room.
    ///
    /// Retroreflective tape returns light along the axis it came in on, so the
    /// torch is not optional here — it is the entire mechanism. With it on and
    /// the exposure pulled down, the tape still clips to white while everything
    /// lit only by the room falls into the floor, and finding the mallet becomes
    /// a threshold rather than a recognition problem.
    ///
    /// `exposureBias` is in stops below what the scene metered at. Around -2.5
    /// keeps the gangsa visible in the preview — which matters, because the
    /// player is looking at this feed — while putting a clear gap between the
    /// marker and the brightest bronze. Push it to -5 or beyond and the frame
    /// goes essentially black except the marker, which is the most robust the
    /// detector gets and the least usable the preview gets.
    ///
    /// The duration ceiling is doing separate work from the brightness. A mallet
    /// crosses a bar fast enough to smear badly at 1/30 s, and a smeared marker
    /// has a centroid halfway through its own travel — so the exposure is capped
    /// short even when the bias alone would not have required it.
    func setMarkerVision(_ on: Bool, exposureBias: Double = -2.5, torchLevel: Float = 0.8) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            self.markerVisionActive = on
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if on {
                    if device.hasTorch, device.isTorchAvailable {
                        try? device.setTorchModeOn(level: min(torchLevel, AVCaptureDevice.maxAvailableTorchLevel))
                    }
                    // White balance locked too: the tracker separates the marker
                    // from a gilded frame by how COLOURLESS it is, and a white
                    // balance that drifts moves that boundary underneath it.
                    if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }

                    guard device.isExposureModeSupported(.custom) else { return }
                    let format = device.activeFormat
                    // Total light currently being gathered, in ISO-seconds — the
                    // one quantity that survives trading duration against gain.
                    let metered = CMTimeGetSeconds(device.exposureDuration) * Double(device.iso)
                    let target = metered * pow(2.0, exposureBias)

                    let minDuration = max(CMTimeGetSeconds(format.minExposureDuration), 1.0 / 8000.0)
                    let maxDuration = min(CMTimeGetSeconds(format.maxExposureDuration), 1.0 / 250.0)
                    let minISO = Double(format.minISO), maxISO = Double(format.maxISO)

                    // Spend the budget on gain before duration: a short exposure
                    // is what kills the smear, so it is the part not to give back.
                    var duration = min(max(target / minISO, minDuration), maxDuration)
                    var iso = target / duration
                    if iso < minISO { iso = minISO; duration = min(max(target / iso, minDuration), maxDuration) }
                    if iso > maxISO { iso = maxISO }

                    device.setExposureModeCustom(duration: CMTimeMakeWithSeconds(duration, preferredTimescale: 1_000_000),
                                                 iso: Float(iso),
                                                 completionHandler: nil)
                } else {
                    if device.hasTorch { device.torchMode = .off }
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
            } catch {
                // Non-fatal, and it degrades honestly: without the torch and the
                // exposure the marker simply is not the brightest thing in frame,
                // the tracker finds nothing, and the screen says so.
                self.markerVisionActive = false
            }
        }
    }

    // MARK: - Orientation

    /// Rotate delivered buffers to the given angle so the frames we classify
    /// match what the preview shows and the coordinate space the overlay rects
    /// live in. Driven by CameraPreview, which is the single source of truth for
    /// orientation — a fixed angle here breaks the moment the device rotates.
    func setVideoRotationAngle(_ angle: CGFloat) {
        //R Called from the preview's updateUIView, which SwiftUI can run very
        //R often. Reconfiguring the connection hops onto the same queue that
        //R delivers frames, so an unchanged angle must cost nothing.
        guard angle != lastRotationAngle else { return }
        lastRotationAngle = angle
        sessionQueue.async { [weak self] in
            guard let connection = self?.videoOutput?.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }

    // MARK: - Configuration (session queue)

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            setStatus(.failed("No back camera available"))
            return
        }
        self.device = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            session.commitConfiguration()
            setStatus(.failed(error.localizedDescription))
            return
        }

        // Start in continuous autofocus/exposure. Framing later opts into a lock.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
            device.unlockForConfiguration()
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        //R The preview stays on the high preset, but the frames we CLASSIFY do
        //R not need to be 1920×1080: every one of them was being rendered to a
        //R full-size CGImage (8MB) thirty times a second, and a dozen of those
        //R sat in the ring buffer. The classifier squashes its crop to 360×360
        //R anyway, so ask AVFoundation for a smaller buffer instead.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 960,
            kCVPixelBufferHeightKey as String: 540,
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        self.videoOutput = videoOutput

        session.commitConfiguration()
        isConfigured = true
    }

    private func setStatus(_ new: Status) {
        DispatchQueue.main.async { [weak self] in self?.status = new }
    }
}

// MARK: - Frame Processing

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Cheapest possible bail-out: rendering a frame nobody will read is the
        // most expensive thing this app does per unit of value.
        guard wantsFrames,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Presentation timestamps ride the same host clock as the audio strike's
        // hostTime, so fusion can align the two without extra bookkeeping.
        let hostTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        frameBuffer.ingest(pixelBuffer: pixelBuffer, hostTime: hostTime)
    }
}

