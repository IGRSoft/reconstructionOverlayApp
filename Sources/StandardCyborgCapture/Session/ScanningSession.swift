//
//  ScanningSession.swift
//
//  ObservableObject that owns all camera/reconstruction state previously
//  managed by ScanningViewController.

#if os(iOS)

import AVFoundation
import Combine
import CoreMotion
import MediaPlayer
import Metal
import StandardCyborgFusion
import StandardCyborgCaptureObjC
import UIKit

@MainActor
public final class ScanningSession: NSObject,
                                    ObservableObject,
                                    MetalLayerClient,
                                    CameraManagerDelegate,
                                    SCReconstructionManagerDelegate {

    // MARK: - Lifecycle (single source of truth for scan state)

    public let lifecycle: ScanningLifecycle

    // MARK: - Published state (drives SwiftUI)

    @Published public private(set) var scanning = false
    @Published public private(set) var elapsedSeconds = 0
    @Published public private(set) var countdownSeconds = 0
    @Published public private(set) var scanDurationSeconds: Int
    @Published public private(set) var distanceMessage: String? = nil
    @Published public private(set) var showScanFailed = false
    @Published public private(set) var completedScan: Scan? = nil
    @Published public private(set) var latestScanThumbnail: UIImage? = nil

    // MARK: - Metal output layer (set by MetalLayerView)

    public var metalLayer: CAMetalLayer? = nil {
        didSet { _metalLayerSnapshot = metalLayer }
    }

    // MARK: - Private

    private let metalDevice = MTLCreateSystemDefaultDevice()!
    private let cameraManager = CameraManager()
    private let motionManager = CMMotionManager()
    private let meshTexturing = SCMeshTexturing()
    private var frameIndex = 0
    private var latestViewMatrix = matrix_identity_float4x4
    private var scanStore: ScanStore!
    private var lifecycleCancellable: AnyCancellable?

    private lazy var algorithmCommandQueue: MTLCommandQueue = metalDevice.makeCommandQueue()!
    private lazy var visualizationCommandQueue: MTLCommandQueue = metalDevice.makeCommandQueue()!
    private lazy var reconstructionManager: SCReconstructionManager = {
        let mgr = SCReconstructionManager(
            device: metalDevice,
            commandQueue: algorithmCommandQueue,
            maxThreadCount: maxReconstructionThreadCount,
            maxICPIterations: lifecycle.configuration.maxICPIterations,
            icpTolerance: lifecycle.configuration.icpTolerance
        )
        mgr.delegate = self
        mgr.includesColorBuffersInMetadata = true
        return mgr
    }()
    private lazy var scanningViewRenderer: ScanningViewRenderer = {
        do {
            return try ScanningViewRenderer(device: metalDevice, commandQueue: visualizationCommandQueue)
        } catch {
            fatalError("Failed to create ScanningViewRenderer: \(error)")
        }
    }()

    private lazy var maxReconstructionThreadCount: Int32 = {
        UIDevice.current.userInterfaceIdiom == .pad ? 4 : 2
    }()

    private var volumeView: MPVolumeView?

    // MARK: - Lifecycle

    public init(configuration: ScanningConfiguration = .default) {
        lifecycle = ScanningLifecycle(configuration: configuration)
        scanDurationSeconds = configuration.defaultScanDurationSeconds
        super.init()
    }

    public func configure(scanStore: ScanStore) {
        self.scanStore = scanStore
        latestScanThumbnail = scanStore.scans.first?.thumbnail
        cameraManager.delegate = self
        cameraManager.configureCaptureSession(
            maxColorResolution: lifecycle.configuration.maxColorResolution,
            maxDepthResolution: lifecycle.configuration.activeDepthResolution,
            maxFramerate: lifecycle.configuration.maxFramerate
        )
        algorithmCommandQueue.label = "ScanningSession.algorithmCommandQueue"
        visualizationCommandQueue.label = "ScanningSession.visualizationCommandQueue"
        _reconstructionManagerRef = reconstructionManager
        _scanningViewRendererRef = scanningViewRenderer
        _meshTexturingRef = meshTexturing
        _useFullResSnapshot = lifecycle.configuration.useFullResolutionDepthFrames
        _stopScanOnReconFailSnapshot = lifecycle.configuration.stopScanOnReconstructionFailure

        lifecycleCancellable = lifecycle.$state
            .sink { [weak self] newState in
                guard let self else { return }
                self._syncPublishedState(newState)
                self._handleStateChange(newState)
            }

        NotificationCenter.default.addObserver(self, selector: #selector(volumeChanged(_:)),
                                               name: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"), object: nil)
    }

    public func startSession() {
        cameraManager.startSession { result in
            switch result {
            case .success: break
            case .configurationFailed:
                print("Camera configuration failed")
            case .notAuthorized:
                break
            }
        }
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion, self.scanning else { return }
            self.reconstructionManager.accumulateDeviceMotion(motion)
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    public func stopSession() {
        cameraManager.stopSession()
        motionManager.stopDeviceMotionUpdates()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    public func installVolumeView(in parent: UIView) {
        let vv = MPVolumeView(frame: CGRect(x: -CGFloat.greatestFiniteMagnitude, y: 0, width: 0, height: 0))
        parent.addSubview(vv)
        volumeView = vv
    }

    // MARK: - Shutter

    public func shutterTapped() {
        switch lifecycle.state {
        case .idle:
            lifecycle.requestStartCountdown()
        case .countdown:
            lifecycle.cancelCountdown()
        case .scanning:
            lifecycle.stopScanning(reason: .finished)
        default:
            break
        }
    }

    public func focusOnTap(at point: CGPoint) {
        guard !scanning else { return }
        cameraManager.focusOnTap(at: point)
    }

    public func setScanDuration(_ seconds: Int) {
        lifecycle.scanDurationSeconds = seconds
        scanDurationSeconds = seconds
    }

    public func showLatestScan(from scanStore: ScanStore) -> Scan? {
        return scanStore.scans.first
    }

    public func dismissCompleted() {
        lifecycle.reset()
        cameraManager.paused = false
        cameraManager.startSession { result in
            if case .configurationFailed = result {
                print("Camera reconfiguration failed after preview dismiss")
            }
        }
    }

    // MARK: - Published state sync

    private func _syncPublishedState(_ state: ScanningState) {
        scanning = state.isScanning
        elapsedSeconds = state.elapsed ?? 0
        countdownSeconds = state.countdownRemaining ?? 0
        if case .failed = state { showScanFailed = true }
        else { showScanFailed = false }
        if case .completed(let ref) = state { completedScan = ref.scan }
        else { completedScan = nil }
    }

    // MARK: - State change handling

    private func _handleStateChange(_ newState: ScanningState) {
        switch newState {
        case .scanning(let elapsed) where elapsed == 0:
            meshTexturing.reset()
            frameIndex = 0
            _frameIndexSnapshot = 0
            _syncSnapshots(for: newState)
        case .idle, .completed, .failed:
            _syncSnapshots(for: newState)
        case .finalizing:
            cameraManager.paused = true
            latestViewMatrix = matrix_identity_float4x4
            _syncSnapshots(for: newState)
            _finalizeScan()
        default:
            break
        }
    }

    private func _finalizeScan() {
        cameraManager.stopSession()
        reconstructionManager.finalize { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let pointCloud = self.reconstructionManager.buildPointCloud()
                let scan = Scan(pointCloud: pointCloud, thumbnail: nil, meshTexturing: self.meshTexturing)
                self.lifecycle.markCompleted(scan)
                self.reconstructionManager.reset()
                self.cameraManager.paused = false
            }
        }
    }

    // MARK: - CameraManagerDelegate

    public nonisolated func cameraDidOutput(colorBuffer: CVPixelBuffer,
                                            colorTime: CMTime,
                                            depthBuffer: CVPixelBuffer,
                                            depthTime: CMTime,
                                            depthCalibrationData: AVCameraCalibrationData) {
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

    // Nonisolated snapshots
    nonisolated(unsafe) private var _scanningSnapshot: Bool = false
    nonisolated(unsafe) private var _viewMatrixSnapshot = matrix_identity_float4x4
    nonisolated(unsafe) private var _useFullResSnapshot: Bool = false
    nonisolated(unsafe) private var _metalLayerSnapshot: CAMetalLayer? = nil
    nonisolated(unsafe) private var _flipsSnapshot: Bool = false
    nonisolated(unsafe) private var _reconstructionManagerRef: SCReconstructionManager!
    nonisolated(unsafe) private var _scanningViewRendererRef: ScanningViewRenderer!

    private func _syncSnapshots(for state: ScanningState) {
        _scanningSnapshot = state.isScanning
        _viewMatrixSnapshot = latestViewMatrix
        _useFullResSnapshot = lifecycle.configuration.useFullResolutionDepthFrames
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
        let message: String?
        if depth.isNaN || depth <= 0 { message = "No face detected" }
        else if depth < lifecycle.configuration.nearDistanceMeters { message = "Move back" }
        else if depth > lifecycle.configuration.farDistanceMeters { message = "Move closer" }
        else { message = nil }
        distanceMessage = message
        lifecycle.feedbackProvider?.distanceGuidanceChanged(message)
    }

    // MARK: - SCReconstructionManagerDelegate

    public nonisolated func reconstructionManager(_ manager: SCReconstructionManager,
                                                  didProcessWith metadata: SCAssimilatedFrameMetadata,
                                                  statistics: SCReconstructionManagerStatistics) {
        let result = metadata.result
        let viewMatrix = metadata.viewMatrix
        let projMatrix = metadata.projectionMatrix
        let succeededCount = statistics.succeededCount
        let shouldStopOnFail = _stopScanOnReconFailSnapshot

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
                let tooFew = succeededCount < self.lifecycle.configuration.failedScanMinFrameCount
                if tooFew {
                    self.lifecycle.stopScanning(reason: .canceled)
                    self.lifecycle.markFailed(.reconstructionFailed(frameCount: Int(succeededCount)))
                    self._dismissFailedAfterDelay()
                } else {
                    self.lifecycle.stopScanning(reason: .finished)
                }
            }
        }
    }

    nonisolated(unsafe) private var _meshTexturingRef: SCMeshTexturing!
    nonisolated(unsafe) private var _frameIndexSnapshot: Int = 0
    nonisolated(unsafe) private var _stopScanOnReconFailSnapshot: Bool = true

    public nonisolated func reconstructionManager(_ manager: SCReconstructionManager, didEncounterAPIError error: Error) {
        print("Reconstruction API error: \(error)")
    }

    private func _dismissFailedAfterDelay() {
        let delaySeconds = lifecycle.configuration.failedScanDismissDelaySeconds
        Task { @MainActor in
            let nanoseconds = UInt64((delaySeconds * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: nanoseconds)
            if case .failed = self.lifecycle.state {
                self.lifecycle.reset()
            }
        }
    }

    // MARK: - Notifications

    @objc private func volumeChanged(_ n: Notification) {
        guard let info = n.userInfo,
              let reason = info["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String,
              reason == "ExplicitVolumeChange" else { return }
        Task { @MainActor in self.shutterTapped() }
    }
}

#endif
