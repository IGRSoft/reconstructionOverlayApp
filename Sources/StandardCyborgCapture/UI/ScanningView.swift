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
    public init(
        configuration: ScanningConfiguration = .default,
        feedbackProvider: (any ScanFeedbackProvider)? = nil,
        onBPLYExport: ((URL) -> Void)? = nil,
        @ViewBuilder overlay: @escaping (ScanningSession) -> Overlay,
        @ViewBuilder previewControls: @escaping (Scan, MeshingService) -> PreviewControls
    ) {
        self.feedbackProvider = feedbackProvider
        self.onBPLYExport = onBPLYExport
        self.overlay = overlay
        self.previewControls = previewControls
        _session = StateObject(wrappedValue: ScanningSession(configuration: configuration))
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
        .fullScreenCover(item: Binding(
            get: { session.completedScan.map { ScanSelection(scan: $0) } },
            set: { if $0 == nil { session.dismissCompleted() } }
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
