//
//  CameraController.swift
//  gomelan
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

    /// Short rolling history of frames, keyed by host time, for vision fusion
    /// (StrikeFusion looks up the frame nearest an audio strike).
    @ObservationIgnored let frameBuffer = FrameBuffer()

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.gomelan.camera.session")
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
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
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
            guard let device = self?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
                device.unlockForConfiguration()
            } catch {
                // Non-fatal: leave whatever mode the device is already in.
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
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
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
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Presentation timestamps ride the same host clock as the audio strike's
        // hostTime, so fusion can align the two without extra bookkeeping.
        let hostTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        frameBuffer.ingest(pixelBuffer: pixelBuffer, hostTime: hostTime)
    }
}

