//
//  BPLYScanningView.swift

#if os(iOS)

import AVFoundation
import Combine
import CoreMotion
import Metal
import StandardCyborgFusion
import StandardCyborgCaptureObjC
import SwiftUI

public struct BPLYScanningView: View {
    @EnvironmentObject private var scanStore: ScanStore

    private let onExport: (URL) -> Void
    private let onDone: () -> Void
    private let feedbackProvider: (any ScanFeedbackProvider)?

    @StateObject private var session: BPLYScanningSession

    private let metalDevice = MTLCreateSystemDefaultDevice()!

    public init(
        configuration: ScanningConfiguration = .default,
        feedbackProvider: (any ScanFeedbackProvider)? = nil,
        onExport: @escaping (URL) -> Void,
        onDone: @escaping () -> Void
    ) {
        self.feedbackProvider = feedbackProvider
        self.onExport = onExport
        self.onDone = onDone
        _session = StateObject(wrappedValue: BPLYScanningSession(configuration: configuration))
    }

    public var body: some View {
        ZStack {
            MetalLayerView(session: session, device: metalDevice)
                .ignoresSafeArea()

            BPLYScanControls(session: session, onDone: {
                session.stopSession()
                onDone()
            })
        }
        .ignoresSafeArea()
        .onAppear {
            session.lifecycle.feedbackProvider = feedbackProvider
            session.configure()
            session.startSession()
        }
        .onDisappear {
            session.stopSession()
        }
        .onChange(of: session.exportURL) { url in
            if let url {
                onExport(url)
                session.dismissExport()
            }
        }
    }
}

// MARK: - BPLYScanningSession

@MainActor
final class BPLYScanningSession: NSObject, ObservableObject, MetalLayerClient {

    let lifecycle: ScanningLifecycle

    @Published private(set) var scanning = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var countdownSeconds = 0
    @Published private(set) var scanDurationSeconds: Int
    @Published private(set) var exportURL: URL? = nil

    init(configuration: ScanningConfiguration = .default) {
        lifecycle = ScanningLifecycle(configuration: configuration)
        scanDurationSeconds = configuration.defaultScanDurationSeconds
        super.init()
    }

    var metalLayer: CAMetalLayer? = nil {
        didSet { _metalLayerRef = metalLayer }
    }

    func focusOnTap(at point: CGPoint) {
        guard !scanning else { return }
        cameraManager.focusOnTap(at: point)
    }

    private let metalDevice = MTLCreateSystemDefaultDevice()!
    private lazy var commandQueue = metalDevice.makeCommandQueue()!
    private lazy var reconstructionManager = SCReconstructionManager(
        device: metalDevice,
        commandQueue: commandQueue,
        maxThreadCount: 2,
        maxICPIterations: lifecycle.configuration.maxICPIterations,
        icpTolerance: lifecycle.configuration.icpTolerance
    )
    private lazy var scanningViewRenderer: ScanningViewRenderer = {
        do {
            return try ScanningViewRenderer(device: metalDevice, commandQueue: commandQueue)
        } catch {
            fatalError("Failed to create ScanningViewRenderer: \(error)")
        }
    }()
    private let cameraManager = CameraManager()
    private let motionManager = CMMotionManager()
    private var bplyAccumulator: BPLYDepthDataAccumulator?
    private var lifecycleCancellable: AnyCancellable?

    nonisolated(unsafe) private var _metalLayerRef: CAMetalLayer?
    nonisolated(unsafe) private var _reconstructionManagerRef: SCReconstructionManager!
    nonisolated(unsafe) private var _rendererRef: ScanningViewRenderer!
    nonisolated(unsafe) private var _scanningSnapshot: Bool = false
    nonisolated(unsafe) private var _useFullResSnapshot: Bool = false
    nonisolated(unsafe) private var _accumulatorRef: BPLYDepthDataAccumulator?

    func configure() {
        cameraManager.delegate = self
        cameraManager.configureCaptureSession(maxColorResolution: lifecycle.configuration.maxColorResolution,
                                              maxDepthResolution: lifecycle.configuration.activeDepthResolution,
                                              maxFramerate: lifecycle.configuration.maxFramerate)
        _reconstructionManagerRef = reconstructionManager
        _rendererRef = scanningViewRenderer
        _useFullResSnapshot = lifecycle.configuration.useFullResolutionDepthFrames

        lifecycleCancellable = lifecycle.$state
            .sink { [weak self] newState in
                guard let self else { return }
                self._syncPublishedState(newState)
                self._handleStateChange(newState)
            }
    }

    func startSession() {
        cameraManager.startSession { _ in }
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion, self.scanning else { return }
            self.bplyAccumulator?.accumulate(deviceMotion: motion)
            self._accumulatorRef = self.bplyAccumulator
        }
    }

    func stopSession() {
        cameraManager.stopSession()
        motionManager.stopDeviceMotionUpdates()
    }

    func shutterTapped() {
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

    func setScanDuration(_ seconds: Int) {
        lifecycle.scanDurationSeconds = seconds
        scanDurationSeconds = seconds
    }
    func dismissExport() { exportURL = nil }

    // MARK: - Published state sync

    private func _syncPublishedState(_ state: ScanningState) {
        scanning = state.isScanning
        elapsedSeconds = state.elapsed ?? 0
        countdownSeconds = state.countdownRemaining ?? 0
    }

    // MARK: - State change handling

    private func _handleStateChange(_ newState: ScanningState) {
        switch newState {
        case .scanning(let elapsed) where elapsed == 0:
            bplyAccumulator = BPLYDepthDataAccumulator()
            _accumulatorRef = bplyAccumulator
            _scanningSnapshot = true
        case .idle:
            _scanningSnapshot = false
        case .finalizing:
            let accumulator = bplyAccumulator
            bplyAccumulator = nil
            _accumulatorRef = nil
            _scanningSnapshot = false
            if let accumulator {
                exportURL = accumulator.exportFrameSequenceToZip()
            }
            Task { @MainActor in self.lifecycle.reset() }
        default:
            break
        }
    }
}

extension BPLYScanningSession: CameraManagerDelegate {
    nonisolated func cameraDidOutput(colorBuffer: CVPixelBuffer,
                                     colorTime: CMTime,
                                     depthBuffer: CVPixelBuffer,
                                     depthTime: CMTime,
                                     depthCalibrationData: AVCameraCalibrationData) {
        let isScanning = _scanningSnapshot
        let useFullRes = _useFullResSnapshot
        let layer = _metalLayerRef

        let pointCloud = _reconstructionManagerRef.reconstructSingleDepthBuffer(
            depthBuffer, colorBuffer: colorBuffer,
            with: depthCalibrationData, smoothingPoints: !useFullRes
        )

        if let layer {
            _rendererRef.draw(colorBuffer: colorBuffer,
                              depthBuffer: depthBuffer,
                              pointCloud: pointCloud,
                              depthCameraCalibrationData: depthCalibrationData,
                              viewMatrix: matrix_identity_float4x4,
                              into: layer,
                              flipsInputHorizontally: false)
        }

        if isScanning {
            _accumulatorRef?.accumulate(colorBuffer: colorBuffer,
                                        colorTime: colorTime,
                                        depthBuffer: depthBuffer,
                                        depthTime: depthTime,
                                        calibrationData: depthCalibrationData)
        }
    }
}

// MARK: - BPLYScanControls

private struct BPLYScanControls: View {
    @ObservedObject var session: BPLYScanningSession
    let onDone: () -> Void

    var body: some View {
        ZStack {
            if session.countdownSeconds > 0 {
                Text("\(session.countdownSeconds)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            VStack {
                HStack {
                    if session.scanning {
                        Text("\(session.elapsedSeconds + 1)")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .padding(.leading, 20)
                    }
                    Spacer()
                    if !session.lifecycle.configuration.tapToStartStop {
                        Text("\(session.scanDurationSeconds) sec")
                            .foregroundStyle(.white)
                            .padding(.trailing, 20)
                    }
                }
                .padding(.top, 60)

                if !session.scanning && !session.lifecycle.configuration.tapToStartStop {
                    Slider(value: Binding(
                        get: { Double(session.scanDurationSeconds) },
                        set: { session.setScanDuration(Int($0)) }
                    ), in: 1...20, step: 1)
                    .padding(.horizontal, 20)
                    .accentColor(.white)
                }

                Spacer()

                HStack(alignment: .center) {
                    Spacer()
                    Button { session.shutterTapped() } label: {
                        Image(session.scanning ? "CameraButtonRecording" : "CameraButton", bundle: .module)
                            .resizable()
                            .frame(width: 72, height: 72)
                    }
                    Spacer()
                    Button("Done", action: onDone)
                        .foregroundStyle(.white)
                        .padding(.trailing, 24)
                }
                .padding(.bottom, 40)
            }
        }
    }
}

#endif
