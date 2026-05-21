//
//  ScanningView.swift

#if os(iOS)

import Metal
import StandardCyborgFusion
import StandardCyborgCaptureObjC
import SwiftUI

/// Top-level SwiftUI scanning view.
///
/// Owns its own ``ScanningSession`` (`@StateObject`) and overlays the
/// ``MetalLayerView`` with consumer-provided overlay content. When the
/// session produces a completed scan, the view internally presents a
/// ``ScanPreviewView`` via `.fullScreenCover` with consumer-provided
/// preview controls.
///
/// Inject a ``ScanStore`` via `.environmentObject(...)` before presentation.
public struct ScanningView<Overlay: View, PreviewControls: View>: View {
    @EnvironmentObject private var scanStore: ScanStore

    @StateObject private var session: ScanningSession

    private let overlay: (ScanningSession) -> Overlay
    private let previewControls: (Scan, MeshingService) -> PreviewControls
    private let feedbackProvider: (any ScanFeedbackProvider)?
    private let onBPLYExport: ((URL) -> Void)?

    /// Whether this view presents its own built-in ``ScanPreviewView`` after
    /// a scan completes. Defaults to `true` so the reference
    /// `Examples/TrueDepthFusion` app keeps showing its post-capture preview.
    /// Consumers that drive their own navigation after a completed scan can
    /// pass `false` to suppress the built-in `.fullScreenCover`.
    private let presentsBuiltInPreview: Bool

    private let metalDevice = MTLCreateSystemDefaultDevice()!

    /// - Parameters:
    ///   - configuration: Scanning behavior (camera resolution, distance
    ///     thresholds, durations, …). Defaults to ``ScanningConfiguration/default``.
    ///   - feedbackProvider: Optional audio/haptic feedback for scan events.
    ///   - overlay: A view builder that receives the ``ScanningSession``
    ///     and returns overlay content layered on top of the Metal preview.
    ///   - previewControls: A view builder that receives the completed
    ///     ``Scan`` and ``MeshingService``, used inside the post-capture
    ///     ``ScanPreviewView``.
    ///   - presentsBuiltInPreview: When `true` (default), a completed scan is
    ///     presented in a built-in ``ScanPreviewView`` via `.fullScreenCover`.
    ///     Pass `false` when the consumer handles post-scan navigation itself.
    public init(
        configuration: ScanningConfiguration = .default,
        feedbackProvider: (any ScanFeedbackProvider)? = nil,
        onBPLYExport: ((URL) -> Void)? = nil,
        cameraManager: (any CameraManagerProtocol)? = nil,
        presentsBuiltInPreview: Bool = true,
        @ViewBuilder overlay: @escaping (ScanningSession) -> Overlay,
        @ViewBuilder previewControls: @escaping (Scan, MeshingService) -> PreviewControls
    ) {
        self.feedbackProvider = feedbackProvider
        self.onBPLYExport = onBPLYExport
        self.presentsBuiltInPreview = presentsBuiltInPreview
        self.overlay = overlay
        self.previewControls = previewControls
        let session: ScanningSession = {
            if let cameraManager {
                return ScanningSession(configuration: configuration, cameraManager: cameraManager)
            } else {
                return ScanningSession(configuration: configuration)
            }
        }()
        _session = StateObject(wrappedValue: session)
    }

    public var body: some View {
        ZStack {
            MetalLayerView(session: session, device: metalDevice)
                .ignoresSafeArea()

            overlay(session)
        }
        .ignoresSafeArea()
        .onAppear {
            session.lifecycle.feedbackProvider = feedbackProvider
            session.configure(scanStore: scanStore)
            session.startSession()
        }
        .onDisappear {
            session.stopSession()
        }
        .onChange(of: session.exportURL) { url in
            if let url {
                onBPLYExport?(url)
                session.dismissExport()
            }
        }
        .fullScreenCover(item: Binding<ScanSelection?>(
            get: {
                // When the consumer opts out of the built-in preview, never
                // present the cover — it would otherwise race the consumer's
                // own post-scan navigation.
                guard presentsBuiltInPreview else { return nil }
                return session.completedScan.map { ScanSelection(scan: $0) }
            },
            set: { newValue in
                if newValue == nil { session.dismissCompleted() }
            }
        )) { selection in
            ScanPreviewView(scan: selection.scan, controls: previewControls)
                .environmentObject(scanStore)
        }
    }

}

// MARK: - ScanSelection

/// Identifiable wrapper around `Scan` so SwiftUI's `.sheet(item:)` /
/// `.fullScreenCover(item:)` modifiers can present a scan.
public struct ScanSelection: Identifiable {
    public let scan: Scan
    public var id: ObjectIdentifier { ObjectIdentifier(scan) }

    public init(scan: Scan) {
        self.scan = scan
    }
}

#endif
