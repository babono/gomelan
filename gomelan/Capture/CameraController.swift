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
    private(set) var latestMallet: DetectedMallet?

    /// Exposed for the preview layer.
    @ObservationIgnored let session = AVCaptureSession()

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.gomelan.camera.session")
    @ObservationIgnored private let detectionService = DetectionService()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var isConfigured = false

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
            guard let device = self?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                device.unlockForConfiguration()
            } catch {
                // Non-fatal: some devices won't allow locking; overlay still works.
            }
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

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
        isConfigured = true
    }

    private func setStatus(_ new: Status) {
        DispatchQueue.main.async { [weak self] in self?.status = new }
    }
}

// MARK: - Frame Processing (Detection)

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let mallet = detectionService.detectMallet(in: pixelBuffer)
        if let mallet {
            DispatchQueue.main.async { [weak self] in
                self?.latestMallet = mallet
            }
        }
    }
}

