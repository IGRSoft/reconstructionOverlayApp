//
//  CameraManager.swift

#if os(iOS)

import AVFoundation
import Foundation
import os
import UIKit

/// Outcome of an AVFoundation capture-session setup attempt initiated by
/// ``CameraManager/startSession(_:)``.
///
/// Returned via the completion block of `startSession`. The caller decides how
/// to respond — for example, by presenting a Settings alert for `.notAuthorized`.
public enum SessionSetupResult: Sendable {
    /// Camera access was granted and the session is fully configured.
    case success
    /// The user has denied camera access or the app lacks `NSCameraUsageDescription`.
    case notAuthorized
    /// Session configuration failed (e.g. no TrueDepth camera, unsupported format).
    case configurationFailed
}

/// Protocol abstraction that mirrors ``CameraManager``'s public API so apps
/// can supply a custom camera pipeline to ``ScanningSession`` — e.g. a mock
/// for tests, a decorator that logs frames, or an alternate AVFoundation
/// configuration (back camera, LiDAR, etc.).
///
/// Conformance is class-only because the type owns reference state (AVCaptureSession,
/// dispatch queues) and is expected to be mutated across threads.
public protocol CameraManagerProtocol: AnyObject {
    var delegate: CameraManagerDelegate? { get set }
    var isFocusLocked: Bool { get set }
    var paused: Bool { get set }

    func configureCaptureSession(maxColorResolution: Int,
                                 maxDepthResolution: Int,
                                 maxFramerate: Int)
    func startSession(_ completion: (@Sendable (SessionSetupResult) -> Void)?)
    func stopSession()
    func focusOnTap(at location: CGPoint)
}

/// Delegate that receives synchronized color + depth frames from
/// ``CameraManager``.
///
/// Callbacks are invoked from a background `_dataOutputQueue` and are
/// `nonisolated` — implementors that are `@MainActor`-bound must hop to
/// MainActor explicitly (see `ScanningSession` for the canonical pattern).
public protocol CameraManagerDelegate: AnyObject {
    func cameraDidOutput(colorBuffer: CVPixelBuffer,
                         colorTime: CMTime,
                         depthBuffer: CVPixelBuffer,
                         depthTime: CMTime,
                         depthCalibrationData: AVCameraCalibrationData)
}

/// Owns the TrueDepth `AVCaptureSession` and emits synchronized color/depth
/// frames to its delegate.
///
/// Construct one per scanning view and call ``configureCaptureSession(maxColorResolution:maxDepthResolution:maxFramerate:)``
/// once before ``startSession(_:)``. All AVFoundation work runs on a private
/// serial session queue; delegate callbacks fire on the data-output queue.
public final class CameraManager: NSObject, AVCaptureDataOutputSynchronizerDelegate, @unchecked Sendable {

    public weak var delegate: CameraManagerDelegate?
    public var isFocusLocked: Bool = false {
        didSet {
            _focus(with: isFocusLocked ? .locked : .continuousAutoFocus,
                   exposureMode: isFocusLocked ? .locked : .continuousAutoExposure,
                   at: CGPoint(x: 0.5, y: 0.5),
                   monitorSubjectAreaChange: !isFocusLocked)
        }
    }

    public override init() {
        super.init()
    }

    /// Configures the AVFoundation capture session for synchronized color + depth output.
    ///
    /// Call this once, early in the view lifecycle (e.g. `viewDidLoad`), before calling
    /// ``startSession(_:)``. The method returns immediately; actual configuration work is
    /// dispatched to the internal session queue.
    ///
    /// **Preconditions**
    /// - Must run on a real device with a front-facing TrueDepth camera (iPhone X or later).
    ///   The simulator has no TrueDepth camera and will produce `.configurationFailed`.
    /// - `Info.plist` must contain `NSCameraUsageDescription`; otherwise the system will
    ///   terminate the process before the authorization prompt appears.
    ///
    /// **Authorization handling**
    /// - `.authorized` — configuration proceeds synchronously on the session queue.
    /// - `.notDetermined` — the session queue is *suspended* while the system prompt is
    ///   shown. Once the user responds, the queue resumes and either continues
    ///   configuration (granted) or records `.notAuthorized` (denied).
    /// - Any other status (`.denied`, `.restricted`) — immediately records `.notAuthorized`
    ///   without presenting a prompt.
    ///
    /// **Threading**
    /// All configuration work runs on the internal `_sessionQueue` (serial, `.userInitiated`).
    /// Do not call AVFoundation session APIs from the main thread after calling this method.
    ///
    /// - Parameters:
    ///   - maxColorResolution: Maximum width (pixels) for the color output. Mapped to the
    ///     nearest `AVCaptureSession.Preset`. Defaults to `1280` (HD 1280×720).
    ///   - maxDepthResolution: Maximum width (pixels) for the depth output. The best
    ///     `kCVPixelFormatType_DepthFloat32` format at or below this width is selected.
    ///     Defaults to `640`.
    ///   - maxFramerate: Target depth frame rate. Passed to
    ///     `activeDepthDataMinFrameDuration`. Defaults to `30` fps.
    public func configureCaptureSession(maxColorResolution: Int = 1280, maxDepthResolution: Int = 640, maxFramerate: Int = 30) {
        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            _sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted { self._sessionQueue_setupResult = .notAuthorized }
                self._sessionQueue.resume()
            })
        default:
            _sessionQueue_setupResult = .notAuthorized
        }

        _sessionQueue.async {
            if self._sessionQueue_setupResult == .success {
                self._sessionQueue_setupResult = self._sessionQueue_configureSession(maxColorResolution: maxColorResolution,
                                                                                     maxDepthResolution: maxDepthResolution,
                                                                                     maxFramerate: maxFramerate)
            }
        }
    }

    /// Starts the capture session and reports the outcome via a completion block on the main queue.
    ///
    /// The method is a no-op unless the setup result from ``configureCaptureSession(maxColorResolution:maxDepthResolution:maxFramerate:)``
    /// is `.success`. For any other result the session is *not* started; the caller must
    /// inspect the result and present appropriate UI.
    ///
    /// - Parameter completion: Optional block invoked on the **main queue** with the final
    ///   `SessionSetupResult`. Called even when the session is not started.
    public func startSession(_ completion: (@Sendable (SessionSetupResult) -> Void)? = nil) {
        _sessionQueue.async {
            let result = self._sessionQueue_setupResult
            switch result {
            case .success:
                // Only set up observers and start the session running if setup succeeded.
                // The assimilation gate is DERIVED from the run-state — do not pre-open it;
                // it opens by derivation once we commit `.running`.
                self._addObservers()

                self._captureSession.startRunning()
                // Commit `.running` only if the session genuinely started delivering.
                // The lock guards the enum only — never held across startRunning().
                if self._captureSession.isRunning {
                    self._stateLock.withLock { $0 = .running }
                }

            case .notAuthorized, .configurationFailed:
                break
            }

            DispatchQueue.main.async {
                completion?(result)
            }
        }
    }

    public func stopSession() {
        // Commit `.stopped` synchronously on the caller thread under `_stateLock` so the
        // assimilation gate (derived from state) shuts immediately — no in-flight
        // synchronized frame can reach ICP across the stop boundary. THEN stop the
        // session asynchronously on the serial session queue. `.stopped` never auto-resumes.
        _stateLock.withLock { $0 = .stopped }

        _sessionQueue.async {
            if self._sessionQueue_setupResult == .success {
                self._captureSession.stopRunning()
            }
        }
    }

    public func focusOnTap(at location: CGPoint) {
        let locationRect = CGRect(origin: location, size: .zero)
        let deviceRect = _videoDataOutput.metadataOutputRectConverted(fromOutputRect: locationRect)

        _focus(with: .autoFocus, exposureMode: .autoExpose, at: deviceRect.origin, monitorSubjectAreaChange: true)
    }

    public var paused: Bool = false {
        didSet {
            // Pure state transition on the caller thread — no `_dataOutputQueue.sync` hop
            // (the gate is now derived and published atomically via `_stateLock`).
            // `paused = true` freezes a running session for finalize/preview;
            // `paused = false` resumes ONLY a `.pausedByApp` session. It never resurrects
            // an app-stop (`.stopped`) or a background-suspend (`.suspended`).
            _stateLock.withLock { state in
                if paused {
                    if state == .running { state = .pausedByApp }
                } else {
                    if state == .pausedByApp { state = .running }
                }
            }
        }
    }

    // MARK: - Properties

    private var _sessionQueue_setupResult: SessionSetupResult = .success
    private let _captureSession = AVCaptureSession()
    private let _sessionQueue = DispatchQueue(label: "Session", qos: DispatchQoS.userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    private let _videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera],
                                                                                mediaType: .video,
                                                                                position: .front)
    private var _videoDeviceInput: AVCaptureDeviceInput!
    private let _dataOutputQueue = DispatchQueue(label: "Video data output", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    private let _videoDataOutput = AVCaptureVideoDataOutput()
    private let _depthDataOutput = AVCaptureDepthDataOutput()
    private var _outputSynchronizer: AVCaptureDataOutputSynchronizer?

    // MARK: - Session run-state (single lock-guarded source of truth)

    /// Single lock-guarded source of truth for the AVCaptureSession run-intent AND
    /// the ICP assimilation gate. Replaces the former session-running intent bool, the
    /// standalone rendering-enabled gate storage, and the `paused` bool's gate writes —
    /// all three collapse into this one enum. Every transition is performed under
    /// `_stateLock`.
    ///
    /// The load-bearing distinction is `.suspended` vs `.pausedByApp`: only
    /// `.suspended` auto-resumes on foreground / interruption-ended. A finalize-time
    /// `.pausedByApp` is therefore never resurrected by a concurrent foreground event —
    /// that is the finalize-gate race fix. See ``architecture-0.md#transition-table``.
    private enum SessionRunState {
        /// App-initiated stop (`stopSession` / finalize). NEVER auto-resumes.
        case stopped
        /// Actively delivering frames; the ONLY state that opens the assimilation gate.
        case running
        /// `paused == true` (finalize freeze / preview pause). Resumes ONLY via `paused = false`.
        case pausedByApp
        /// Background or AVCaptureSession interruption. Auto-resumes on foreground / interruption-ended.
        case suspended
    }

    private let _stateLock = OSAllocatedUnfairLock(initialState: SessionRunState.stopped)

    /// The assimilation gate, derived — never stored independently. True iff the
    /// session is actively running. Read by ``dataOutputSynchronizer(_:didOutput:)``
    /// on `_dataOutputQueue` under `_stateLock` so it can never disagree with the
    /// run-state.
    private var _isAssimilationOpen: Bool {
        _stateLock.withLock { $0 == .running }
    }

    // MARK: - Observers

    private func _addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError, object: _captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: _captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: _captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange),
                                               name: .AVCaptureDeviceSubjectAreaDidChange,
                                               object: _videoDeviceInput.device)
    }

    @objc private func sessionWasInterrupted(notification: NSNotification) {
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
        }

        // Transition `.running → .suspended` synchronously on the notification thread under
        // `_stateLock` so the derived assimilation gate shuts immediately (no in-flight
        // synchronized frame reaches ICP across the interruption boundary), then suspend the
        // session on the serial session queue. NO-OP from `.pausedByApp` (finalize/preview must
        // not become auto-resumable) or `.stopped`. `.suspended` is the auto-resume token.
        let didSuspend = _stateLock.withLock { state -> Bool in
            if state == .running { state = .suspended; return true }
            return false
        }
        guard didSuspend else { return }
        _sessionQueue.async {
            self._sessionQueue_pauseForSuspend()
        }
    }

    @objc private func sessionInterruptionEnded(notification: NSNotification) {
        // Resume on the session queue iff the session was `.suspended`. The source-state guard
        // is taken under `_stateLock` BEFORE dispatching. The gate re-opens by derivation only
        // after startRunning() confirms isRunning inside the helper.
        _sessionQueue_resumeIfSuspended()
    }

    @objc private func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }

        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")

        // Automatically try to restart the session if media services were reset. A media-services
        // reset can fire while nominally `.running` (the session died under us), so recovery
        // routes through the SAME resume helper as foreground/interruption-ended but with a
        // source-state guard that accepts `.running` AS WELL AS `.suspended`. It is still a NO-OP
        // from `.pausedByApp`/`.stopped`, so a media reset during finalize never resurrects frame
        // flow. This both shares the resume logic and preserves the finalize invariant.
        if error.code == .mediaServicesWereReset {
            _sessionQueue_resume(acceptingSources: [.running, .suspended])
        }
    }

    @objc private func subjectAreaDidChange(notification: NSNotification) {
        guard !isFocusLocked else { return }

        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        _focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }

    @objc private func didEnterBackground(notification: NSNotification) {
        // Transition `.running → .suspended` synchronously on the notification thread under
        // `_stateLock` so the derived gate shuts immediately — before the async stop runs — then
        // suspend the session on the serial session queue. NO-OP from `.pausedByApp` (a
        // finalize/preview pause must NOT become auto-resumable) or `.stopped`. No reconstruction
        // state is reset (pause-and-resume policy). Shares the suspend helper with
        // `sessionWasInterrupted`.
        let didSuspend = _stateLock.withLock { state -> Bool in
            if state == .running { state = .suspended; return true }
            return false
        }
        guard didSuspend else { return }
        _sessionQueue.async {
            self._sessionQueue_pauseForSuspend()
        }
    }

    @objc private func willEnterForeground(notification: NSNotification) {
        // Resume iff the session was `.suspended`. Do NOT re-open the gate synchronously — that
        // was the original bug: it re-opened ICP assimilation before the session was restarted,
        // feeding the solver garbage frames. The shared helper takes the source-state guard under
        // `_stateLock` and re-opens the gate by derivation only after startRunning() confirms.
        _sessionQueue_resumeIfSuspended()
    }

    // MARK: - AVCaptureDataOutputSynchronizerDelegate

    public func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                       didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection)
    {
        guard _isAssimilationOpen else { return }

        guard
            let syncedDepthData: AVCaptureSynchronizedDepthData =
                    synchronizedDataCollection.synchronizedData(for: _depthDataOutput) as? AVCaptureSynchronizedDepthData,
            let syncedVideoData: AVCaptureSynchronizedSampleBufferData =
                    synchronizedDataCollection.synchronizedData(for: _videoDataOutput) as? AVCaptureSynchronizedSampleBufferData
        else { return /* Only work on synced pairs */ }

        guard !syncedDepthData.depthDataWasDropped &&
              !syncedVideoData.sampleBufferWasDropped
        else { return }

        let depthData = syncedDepthData.depthData
        let depthBuffer = depthData.depthDataMap
        let sampleBuffer = syncedVideoData.sampleBuffer
        guard let colorBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let depthCalibrationData = depthData.cameraCalibrationData
        else { return }

        let colorTime = syncedVideoData.timestamp
        let depthTime = syncedDepthData.timestamp

        delegate?.cameraDidOutput(colorBuffer: colorBuffer,
                                  colorTime: colorTime,
                                  depthBuffer: depthBuffer,
                                  depthTime: depthTime,
                                  depthCalibrationData: depthCalibrationData)
    }

    // MARK: - Internal

    private func _sessionQueue_configureSession(maxColorResolution: Int,
                                                maxDepthResolution: Int,
                                                maxFramerate: Int) -> SessionSetupResult
    {
        guard let videoDevice = _videoDeviceDiscoverySession.devices.first else {
            print("Could not find any video device")
            return .configurationFailed
        }
        do {
            _videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Could not create video device input: \(error)")
            return .configurationFailed
        }
        guard _captureSession.canAddInput(_videoDeviceInput) else {
            print("Could not add video device input to the session")
            return .configurationFailed
        }
        guard _captureSession.canAddOutput(_videoDataOutput) else {
            print("Could not add video data output to the session")
            return .configurationFailed
        }
        guard _captureSession.canAddOutput(_depthDataOutput) else {
            print("Could not add depth data output to the session")
            return .configurationFailed
        }

        _captureSession.beginConfiguration()
        _captureSession.sessionPreset = AVCaptureSession.Preset(maxWidth: maxColorResolution)
        _captureSession.addInput(_videoDeviceInput)
        _captureSession.addOutput(_videoDataOutput)
        _captureSession.addOutput(_depthDataOutput)
        _videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        _videoDataOutput.alwaysDiscardsLateVideoFrames = true
        _depthDataOutput.isFilteringEnabled = false
        _depthDataOutput.alwaysDiscardsLateDepthData = true

        if let captureConnection = _videoDataOutput.connection(with: AVMediaType.video) {
            if captureConnection.isCameraIntrinsicMatrixDeliverySupported {
                captureConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }

        if let connection = _depthDataOutput.connection(with: .depthData) {
            connection.isEnabled = true
        } else {
            print("No AVCaptureConnection")
        }

        // Search for highest resolution with half-point depth values
        let depthFormats = videoDevice.activeFormat.supportedDepthDataFormats
        let selectedFormat = depthFormats.filter {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
        }.filter {
             CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <= maxDepthResolution
        }.max { first, second in
                CMVideoFormatDescriptionGetDimensions(first.formatDescription).width
              < CMVideoFormatDescriptionGetDimensions(second.formatDescription).width
        }

        do {
            try videoDevice.lockForConfiguration()
            videoDevice.activeDepthDataFormat = selectedFormat
            videoDevice.activeDepthDataMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(maxFramerate))
            // DEV: This seems to be coming in as sRGB, as evidenced by the result of `videoDevice.activeFormat`
            videoDevice.unlockForConfiguration()
        } catch {
            print("Could not lock device for configuration: \(error)")
            _captureSession.commitConfiguration()
            return .configurationFailed
        }

        // Use an AVCaptureDataOutputSynchronizer to synchronize the video data and depth data outputs.
        // The first output in the dataOutputs array, in this case the AVCaptureVideoDataOutput, is the "master" output.
        _outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [_videoDataOutput, _depthDataOutput])
        _outputSynchronizer!.setDelegate(self, queue: _dataOutputQueue)
        _captureSession.commitConfiguration()

        return .success
    }

    // MARK: - Lifecycle pause / resume (serial session queue only)

    /// Suspends the running capture session for a background / interruption event.
    ///
    /// **Must be called only from inside a `_sessionQueue.async` block.** The state has already
    /// been transitioned to `.suspended` synchronously by the caller (which also shut the derived
    /// assimilation gate). This helper only performs the AVFoundation stop.
    ///
    /// Idempotent: the `isRunning` guard makes a duplicate call (e.g. both `didEnterBackground`
    /// and `sessionWasInterrupted` firing) a no-op. The `.suspended` state is the auto-resume
    /// token consumed by `_sessionQueue_resume(acceptingSources:)` on foreground.
    private func _sessionQueue_pauseForSuspend() {
        if _captureSession.isRunning {
            _captureSession.stopRunning()
        }
    }

    /// Convenience: resume a session that was suspended for background / interruption.
    /// Source-state guard is `.suspended` only — an app-stop (`.stopped`) or a finalize/preview
    /// pause (`.pausedByApp`) is never resurrected.
    private func _sessionQueue_resumeIfSuspended() {
        _sessionQueue_resume(acceptingSources: [.suspended])
    }

    /// Shared resume helper for foreground / interruption-ended / media-services-reset recovery.
    ///
    /// Takes the source-state guard under `_stateLock` on the CALLER thread, then dispatches the
    /// AVFoundation `startRunning()` to the serial session queue (the lock is NOT held across the
    /// blocking AVFoundation call). `.running` is re-committed only after `isRunning` confirms, so
    /// the derived assimilation gate opens only once the session is genuinely delivering — and the
    /// drop/unpaired guards in `dataOutputSynchronizer` reject non-synchronized frames in that
    /// window.
    ///
    /// - Parameter acceptingSources: the set of source states from which a resume is allowed.
    ///   Foreground / interruption-ended pass `[.suspended]`; `mediaServicesWereReset` passes
    ///   `[.running, .suspended]` (a media reset can fire while nominally running). Both are a
    ///   NO-OP from `.pausedByApp` / `.stopped`.
    private func _sessionQueue_resume(acceptingSources: Set<SessionRunState>) {
        let shouldResume = _stateLock.withLock { acceptingSources.contains($0) }
        guard shouldResume else { return }

        _sessionQueue.async {
            if !self._captureSession.isRunning {
                self._captureSession.startRunning()
            }
            if self._captureSession.isRunning {
                // Commit `.running` (gate opens by derivation). Lock guards the enum only —
                // never held across startRunning().
                self._stateLock.withLock { $0 = .running }
            }
        }
    }

    private func _focus(with focusMode: AVCaptureDevice.FocusMode,
                        exposureMode: AVCaptureDevice.ExposureMode,
                        at devicePoint: CGPoint,
                        monitorSubjectAreaChange: Bool)
    {
        _sessionQueue.async {
            let videoDevice = self._videoDeviceInput.device

            do {
                try videoDevice.lockForConfiguration()
                if videoDevice.isFocusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
                    videoDevice.focusPointOfInterest = devicePoint
                    videoDevice.focusMode = focusMode
                }

                if videoDevice.isExposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                    videoDevice.exposurePointOfInterest = devicePoint
                    videoDevice.exposureMode = exposureMode
                }

                videoDevice.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                videoDevice.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }

}

extension CameraManager: CameraManagerProtocol {}

// MARK: - Test Info
// @test-file: (none — no Swift test target for StandardCyborgCapture; AVCaptureSession is unmockable)
// @test-coverage: Lifecycle pause/resume verified by build + design reasoning (AR §10). The pure
//   resume predicate is the source-state guard in `_sessionQueue_resume(acceptingSources:)`
//   (resume only from `.suspended`, or `.running|.suspended` for media-services reset); it is
//   inseparable from AVCaptureSession.isRunning, so it cannot be unit-tested without a device or a
//   new test seam that would breach the single-file scope. See developer-0.md § Decisions d4.
// @doc-refs: .context/architecture-0.md#resume-correctness, .context/teamlead-0.md#acceptance-checkpoints

fileprivate extension AVCaptureSession.Preset {
    init(maxWidth: Int) {
        switch maxWidth {
        case 1...352:
            self = .cif352x288
        case 353...640:
            self = .vga640x480
        case 641...1280:
            self = .hd1280x720
        case 1281...1920:
            self = .hd1920x1080
        case 1921..<3840:
            self = .hd4K3840x2160
        default:
            self = .photo
        }
    }
}

#endif
