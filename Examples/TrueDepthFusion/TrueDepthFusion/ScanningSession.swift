//
//  ScanningSession.swift
//
//  ObservableObject that owns all camera/reconstruction state previously
//  managed by ScanningViewController.

import AVFoundation
import Combine
import CoreMotion
import MediaPlayer
import Metal
import StandardCyborgFusion
import TrueDepthFusionObjC
import UIKit

@MainActor
final class ScanningSession: NSObject, ObservableObject, CameraManagerDelegate, SCReconstructionManagerDelegate {

    // MARK: - Published state (drives SwiftUI)

    @Published private(set) var scanning = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var countdownSeconds = 0
    @Published private(set) var scanDurationSeconds = 5
    @Published private(set) var distanceMessage: String? = nil
    @Published private(set) var showScanFailed = false
    @Published private(set) var completedScan: Scan? = nil
    @Published private(set) var latestScanThumbnail: UIImage? = nil

    // MARK: - Metal output layer (set by MetalLayerView)

    var metalLayer: CAMetalLayer? = nil {
        didSet { _metalLayerSnapshot = metalLayer }
    }

    // MARK: - Private

    private let metalDevice = MTLCreateSystemDefaultDevice()!
    private let cameraManager = CameraManager()
    private let motionManager = CMMotionManager()
    private let meshTexturing = SCMeshTexturing()
    private var frameIndex = 0
    private var latestViewMatrix = matrix_identity_float4x4
    private var scanningTimer: Timer?
    private var scanStore: ScanStore!

    private enum TerminationReason { case canceled, finished }

    private lazy var algorithmCommandQueue: MTLCommandQueue = metalDevice.makeCommandQueue()!
    private lazy var visualizationCommandQueue: MTLCommandQueue = metalDevice.makeCommandQueue()!
    private lazy var reconstructionManager: SCReconstructionManager = {
        let mgr = SCReconstructionManager(device: metalDevice, commandQueue: algorithmCommandQueue, maxThreadCount: maxReconstructionThreadCount)
        mgr.delegate = self
        mgr.includesColorBuffersInMetadata = true
        return mgr
    }()
    private lazy var scanningViewRenderer = ScanningViewRenderer(device: metalDevice, commandQueue: visualizationCommandQueue)

    private var tapToStartStop: Bool { UserDefaults.standard.bool(forKey: "tap_to_start_stop") }
    private var useFullResolutionDepthFrames: Bool { UserDefaults.standard.bool(forKey: "full_resolution_depth_frames", defaultValue: false) }
    private var stopScanOnReconFail: Bool { UserDefaults.standard.bool(forKey: "stop_scanning_on_reconstruction_failure", defaultValue: true) }
    private let failedScanShowPreviewMinFrameCount = 50

    private lazy var maxReconstructionThreadCount: Int32 = {
        UIDevice.current.userInterfaceIdiom == .pad ? 4 : 2
    }()

    // Volume button
    private var volumeView: MPVolumeView?

    // MARK: - Lifecycle

    func configure(scanStore: ScanStore) {
        self.scanStore = scanStore
        latestScanThumbnail = scanStore.scans.first?.thumbnail
        cameraManager.delegate = self
        cameraManager.configureCaptureSession(
            maxColorResolution: 1920,
            maxDepthResolution: useFullResolutionDepthFrames ? 640 : 320,
            maxFramerate: 30
        )
        algorithmCommandQueue.label = "ScanningSession.algorithmCommandQueue"
        visualizationCommandQueue.label = "ScanningSession.visualizationCommandQueue"
        // Expose refs to nonisolated camera/reconstruction callbacks
        _reconstructionManagerRef = reconstructionManager
        _scanningViewRendererRef = scanningViewRenderer
        _meshTexturingRef = meshTexturing
        _useFullResSnapshot = useFullResolutionDepthFrames
        _stopScanOnReconFailSnapshot = stopScanOnReconFail
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged(_:)),
                                               name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(volumeChanged(_:)),
                                               name: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"), object: nil)
    }

    func startSession() {
        cameraManager.startSession { result in
            switch result {
            case .success: break
            case .configurationFailed:
                print("Camera configuration failed")
            case .notAuthorized:
                break  // Handled by permission request at app level
            }
        }
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion, self.scanning else { return }
            self.reconstructionManager.accumulateDeviceMotion(motion)
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopSession() {
        cameraManager.stopSession()
        motionManager.stopDeviceMotionUpdates()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func installVolumeView(in parent: UIView) {
        let vv = MPVolumeView(frame: CGRect(x: -CGFloat.greatestFiniteMagnitude, y: 0, width: 0, height: 0))
        parent.addSubview(vv)
        volumeView = vv
    }

    // MARK: - Shutter

    func shutterTapped() {
        if scanning {
            AudioAndHapticEngine.shared.scanningFinished()
            stopScanning(reason: .finished)
        } else if countdownSeconds > 0 {
            AudioAndHapticEngine.shared.scanningCanceled()
            cancelCountdown()
        } else {
            startCountdown { [weak self] in self?.startScanning() }
        }
    }

    func focusOnTap(at point: CGPoint) {
        guard !scanning else { return }
        cameraManager.focusOnTap(at: point)
    }

    func setScanDuration(_ seconds: Int) {
        scanDurationSeconds = seconds
    }

    func showLatestScan(from scanStore: ScanStore) -> Scan? {
        return scanStore.scans.first
    }

    func dismissCompleted() {
        completedScan = nil
    }

    // MARK: - CameraManagerDelegate
    // NOTE: Called from camera session queue (background thread).
    // All work done inline here (nonisolated). @MainActor state is
    // read via nonisolated(unsafe) snapshots and written via DispatchQueue.main.

    nonisolated func cameraDidOutput(colorBuffer: CVPixelBuffer,
                                     colorTime: CMTime,
                                     depthBuffer: CVPixelBuffer,
                                     depthTime: CMTime,
                                     depthCalibrationData: AVCameraCalibrationData) {
        // Snapshot @MainActor state without crossing actor boundary
        let isScanning = _scanningSnapshot
        let viewMatrix = _viewMatrixSnapshot
        let useFullRes = _useFullResSnapshot
        let layer = _metalLayerSnapshot
        let flips = _flipsSnapshot

        let pointCloud: SCPointCloud
        if isScanning {
            pointCloud = _reconstructionManagerRef.buildPointCloud()
        } else {
            pointCloud = _reconstructionManagerRef.reconstructSingleDepthBuffer(
                depthBuffer, colorBuffer: colorBuffer,
                with: depthCalibrationData,
                smoothingPoints: !useFullRes
            )
        }

        if let layer {
            _scanningViewRendererRef.draw(
                colorBuffer: colorBuffer,
                depthBuffer: depthBuffer,
                pointCloud: pointCloud,
                depthCameraCalibrationData: depthCalibrationData,
                viewMatrix: isScanning ? viewMatrix : matrix_identity_float4x4,
                into: layer,
                flipsInputHorizontally: flips
            )
        }

        if isScanning {
            _reconstructionManagerRef.accumulate(depthBuffer: depthBuffer,
                                                 colorBuffer: colorBuffer,
                                                 calibrationData: depthCalibrationData)
        } else {
            _updateDistanceGuidanceNonisolated(from: depthBuffer)
        }
    }

    // Nonisolated snapshots of @MainActor state — written on main, read on bg.
    // Swift 6: safe because writes are serialized on MainActor and reads are
    // on a single serial camera queue (no torn reads for value types).
    nonisolated(unsafe) private var _scanningSnapshot: Bool = false
    nonisolated(unsafe) private var _viewMatrixSnapshot = matrix_identity_float4x4
    nonisolated(unsafe) private var _useFullResSnapshot: Bool = false
    nonisolated(unsafe) private var _metalLayerSnapshot: CAMetalLayer? = nil
    nonisolated(unsafe) private var _flipsSnapshot: Bool = false

    // Nonisolated references — set once during configure() on MainActor.
    nonisolated(unsafe) private var _reconstructionManagerRef: SCReconstructionManager!
    nonisolated(unsafe) private var _scanningViewRendererRef: ScanningViewRenderer!

    private func _syncSnapshots() {
        _scanningSnapshot = scanning
        _viewMatrixSnapshot = latestViewMatrix
        _useFullResSnapshot = useFullResolutionDepthFrames
        _metalLayerSnapshot = metalLayer
        _flipsSnapshot = reconstructionManager.flipsInputHorizontally
    }

    nonisolated private func _updateDistanceGuidanceNonisolated(from depthBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else { return }
        let cx = width / 2, cy = height / 2
        var sum: Float = 0, count = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let offset = (cy + dy) * bytesPerRow / 4 + (cx + dx)
                let depth = base.assumingMemoryBound(to: Float32.self)[offset]
                if depth.isFinite && depth > 0 { sum += depth; count += 1 }
            }
        }
        let depth = count > 0 ? sum / Float(count) : Float.nan
        DispatchQueue.main.async { self.updateDistanceLabel(depth: depth) }
    }

    private func updateDistanceLabel(depth: Float) {
        guard !scanning else { distanceMessage = nil; return }
        if depth.isNaN || depth <= 0 { distanceMessage = "No face detected" }
        else if depth < 0.25 { distanceMessage = "Move back" }
        else if depth > 0.60 { distanceMessage = "Move closer" }
        else { distanceMessage = nil }
    }

    // MARK: - SCReconstructionManagerDelegate
    // Called on reconstruction thread (nonisolated). Extract Sendable values
    // inline; dispatch to MainActor only with those values.

    nonisolated func reconstructionManager(_ manager: SCReconstructionManager,
                                           didProcessWith metadata: SCAssimilatedFrameMetadata,
                                           statistics: SCReconstructionManagerStatistics) {
        let result = metadata.result
        let viewMatrix = metadata.viewMatrix
        let projMatrix = metadata.projectionMatrix
        let succeededCount = statistics.succeededCount
        let shouldStopOnFail = _stopScanOnReconFailSnapshot

        // Update meshTexturing inline on reconstruction thread (same thread as finalize).
        // SCMeshTexturing is @unchecked Sendable and only accessed here + finalize block.
        if result == .succeeded || result == .poorTracking {
            _meshTexturingRef.cameraCalibrationData = manager.latestCameraCalibrationData
            _meshTexturingRef.cameraCalibrationFrameWidth = manager.latestCameraCalibrationFrameWidth
            _meshTexturingRef.cameraCalibrationFrameHeight = manager.latestCameraCalibrationFrameHeight
            let currentIndex = _frameIndexSnapshot
            if currentIndex % 5 == 0, let cb = metadata.colorBuffer?.takeUnretainedValue() {
                _meshTexturingRef.saveColorBufferForReconstruction(cb, withViewMatrix: viewMatrix, projectionMatrix: projMatrix)
            }
            _frameIndexSnapshot += 1
        }

        DispatchQueue.main.async {
            self.latestViewMatrix = viewMatrix
            self.frameIndex = self._frameIndexSnapshot
            self._viewMatrixSnapshot = viewMatrix
            if shouldStopOnFail && result == .failed {
                let tooFew = succeededCount < self.failedScanShowPreviewMinFrameCount
                self.stopScanning(reason: tooFew ? .canceled : .finished)
                self.showScanFailedBriefly()
            }
        }
    }

    // nonisolated(unsafe) refs for reconstruction thread access
    nonisolated(unsafe) private var _meshTexturingRef: SCMeshTexturing!
    nonisolated(unsafe) private var _frameIndexSnapshot: Int = 0

    nonisolated(unsafe) private var _stopScanOnReconFailSnapshot: Bool = true

    nonisolated func reconstructionManager(_ manager: SCReconstructionManager, didEncounterAPIError error: Error) {
        print("Reconstruction API error: \(error)")
    }

    // MARK: - Notifications

    @objc private func thermalStateChanged(_ n: Notification) {
        guard let info = n.object as? ProcessInfo, info.thermalState == .critical else { return }
        Task { @MainActor in
            if self.scanning { self.stopScanning(reason: .finished) }
        }
    }

    @objc private func volumeChanged(_ n: Notification) {
        guard let info = n.userInfo,
              let reason = info["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String,
              reason == "ExplicitVolumeChange" else { return }
        Task { @MainActor in self.shutterTapped() }
    }

    // MARK: - Private scanning logic

    private func startCountdown(_ completion: @escaping () -> Void) {
        countdownSeconds = 3
        iterateCountdown(completion)
    }

    private func cancelCountdown() {
        countdownSeconds = 0
    }

    private func iterateCountdown(_ completion: @escaping () -> Void) {
        AudioAndHapticEngine.shared.countdownCountedDown()
        if countdownSeconds == 0 { completion(); return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if self.countdownSeconds > 0 {
                self.countdownSeconds -= 1
                self.iterateCountdown(completion)
            }
        }
    }

    private func startScanning() {
        AudioAndHapticEngine.shared.scanningBegan()
        scanningTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsedSeconds += 1
                if !self.tapToStartStop && self.elapsedSeconds >= self.scanDurationSeconds {
                    self.stopScanning(reason: .finished)
                }
            }
        }
        RunLoop.current.add(scanningTimer!, forMode: .default)
        elapsedSeconds = 0
        scanning = true
        meshTexturing.reset()
        frameIndex = 0
        _frameIndexSnapshot = 0
        _syncSnapshots()
    }

    private func stopScanning(reason: TerminationReason) {
        guard scanning else { return }
        cameraManager.paused = true
        scanning = false
        scanningTimer?.invalidate()
        scanningTimer = nil
        elapsedSeconds = 0
        latestViewMatrix = matrix_identity_float4x4
        _syncSnapshots()

        switch reason {
        case .canceled: AudioAndHapticEngine.shared.scanningCanceled()
        case .finished: AudioAndHapticEngine.shared.scanningFinished()
        }

        if reason == .finished {
            cameraManager.stopSession()
            reconstructionManager.finalize { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    let pointCloud = self.reconstructionManager.buildPointCloud()
                    let scan = Scan(pointCloud: pointCloud, thumbnail: nil, meshTexturing: self.meshTexturing)
                    self.completedScan = scan
                    self.reconstructionManager.reset()
                    self.cameraManager.paused = false
                }
            }
        } else {
            reconstructionManager.reset()
            cameraManager.paused = false
        }
    }

    private func showScanFailedBriefly() {
        showScanFailed = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_800_000_000)
            self.showScanFailed = false
        }
    }
}
