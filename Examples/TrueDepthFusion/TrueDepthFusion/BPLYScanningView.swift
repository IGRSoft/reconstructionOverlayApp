//
//  BPLYScanningView.swift

import AVFoundation
import CoreMotion
import Metal
import StandardCyborgFusion
import SwiftUI
import StandardCyborgCapture

struct BPLYScanningView: View {
    @EnvironmentObject private var scanStore: ScanStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session = BPLYScanningSession()
    @State private var shareItems: [Any]?

    private let metalDevice = MTLCreateSystemDefaultDevice()!

    var body: some View {
        ZStack {
            MetalLayerView(session: session, device: metalDevice)
                .ignoresSafeArea()

            BPLYScanControls(session: session, onDone: {
                session.stopSession()
                dismiss()
            })
        }
        .ignoresSafeArea()
        .onAppear {
            session.configure()
            session.startSession()
        }
        .onDisappear {
            session.stopSession()
        }
        .onChange(of: session.exportURL) { url in
            if let url { shareItems = [url] }
        }
        .sheet(item: Binding(
            get: { shareItems.map { ShareableURL(url: $0[0] as! URL) } },
            set: { if $0 == nil { shareItems = nil; session.dismissExport() } }
        )) { s in
            ActivityView(activityItems: [s.url], applicationActivities: nil)
                .ignoresSafeArea()
        }
    }
}

// MARK: - ShareableURL

private struct ShareableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - BPLYScanningSession

@MainActor
final class BPLYScanningSession: NSObject, ObservableObject, MetalLayerClient {

    @Published private(set) var scanning = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var countdownSeconds = 0
    @Published private(set) var scanDurationSeconds = 5
    @Published private(set) var exportURL: URL? = nil

    // MetalLayerClient conformance
    var metalLayer: CAMetalLayer? = nil {
        didSet { _metalLayerRef = metalLayer }
    }
    func focusOnTap(at point: CGPoint) {
        guard !scanning else { return }
        cameraManager.focusOnTap(at: point)
    }

    private let metalDevice = MTLCreateSystemDefaultDevice()!
    private lazy var commandQueue = metalDevice.makeCommandQueue()!
    private lazy var reconstructionManager = SCReconstructionManager(device: metalDevice, commandQueue: commandQueue, maxThreadCount: 2)
    private lazy var scanningViewRenderer = ScanningViewRenderer(device: metalDevice, commandQueue: commandQueue)
    private let cameraManager = CameraManager()
    private let motionManager = CMMotionManager()
    private var scanningTimer: Timer?
    private var bplyAccumulator: BPLYDepthDataAccumulator?

    private enum TerminationReason { case canceled, finished }
    private var tapToStartStop: Bool { UserDefaults.standard.bool(forKey: "tap_to_start_stop") }
    private var useFullResolution: Bool { UserDefaults.standard.bool(forKey: "full_resolution_depth_frames", defaultValue: false) }

    // nonisolated(unsafe) snapshots for camera delegate
    nonisolated(unsafe) private var _metalLayerRef: CAMetalLayer?
    nonisolated(unsafe) private var _reconstructionManagerRef: SCReconstructionManager!
    nonisolated(unsafe) private var _rendererRef: ScanningViewRenderer!
    nonisolated(unsafe) private var _scanningSnapshot: Bool = false
    nonisolated(unsafe) private var _useFullResSnapshot: Bool = false
    nonisolated(unsafe) private var _accumulatorRef: BPLYDepthDataAccumulator?

    func configure() {
        cameraManager.delegate = self
        cameraManager.configureCaptureSession(maxColorResolution: 1920,
                                              maxDepthResolution: useFullResolution ? 640 : 320,
                                              maxFramerate: 30)
        _reconstructionManagerRef = reconstructionManager
        _rendererRef = scanningViewRenderer
        _useFullResSnapshot = useFullResolution
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
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
        if scanning {
            stopScanning(reason: .finished)
        } else if countdownSeconds > 0 {
            AudioAndHapticEngine.shared.scanningCanceled()
            countdownSeconds = 0
        } else {
            startCountdown { [weak self] in self?.startScanning() }
        }
    }

    func setScanDuration(_ seconds: Int) { scanDurationSeconds = seconds }
    func dismissExport() { exportURL = nil }

    private func startCountdown(_ completion: @escaping () -> Void) {
        countdownSeconds = 3
        iterateCountdown(completion)
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
        bplyAccumulator = BPLYDepthDataAccumulator()
        _accumulatorRef = bplyAccumulator
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
        _scanningSnapshot = true
    }

    private func stopScanning(reason: TerminationReason) {
        guard scanning else { return }
        let accumulator = bplyAccumulator
        bplyAccumulator = nil
        _accumulatorRef = nil
        scanning = false
        _scanningSnapshot = false
        scanningTimer?.invalidate()
        scanningTimer = nil
        elapsedSeconds = 0
        switch reason {
        case .canceled: AudioAndHapticEngine.shared.scanningCanceled()
        case .finished: AudioAndHapticEngine.shared.scanningFinished()
        }
        if reason == .finished, let accumulator {
            exportURL = accumulator.exportFrameSequenceToZip()
        }
    }

    @objc private func thermalStateChanged(_ n: Notification) {
        guard let info = n.object as? ProcessInfo, info.thermalState == .critical else { return }
        Task { @MainActor in if self.scanning { self.stopScanning(reason: .finished) } }
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

    private var tapToStartStop: Bool {
        UserDefaults.standard.bool(forKey: "tap_to_start_stop")
    }

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
                    if !tapToStartStop {
                        Text("\(session.scanDurationSeconds) sec")
                            .foregroundStyle(.white)
                            .padding(.trailing, 20)
                    }
                }
                .padding(.top, 60)

                if !session.scanning && !tapToStartStop {
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
                        Image(session.scanning ? "CameraButtonRecording" : "CameraButton")
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
