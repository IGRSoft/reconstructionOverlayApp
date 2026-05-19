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

    @StateObject private var session = ScanningSession()

    private let overlay: (ScanningSession) -> Overlay
    private let previewControls: (Scan, MeshingService) -> PreviewControls
    private weak var feedbackProvider: ScanFeedbackProvider?

    private let metalDevice = MTLCreateSystemDefaultDevice()!

    /// - Parameters:
    ///   - feedbackProvider: Optional audio/haptic feedback for scan events.
    ///   - overlay: A view builder that receives the ``ScanningSession``
    ///     and returns overlay content layered on top of the Metal preview.
    ///   - previewControls: A view builder that receives the completed
    ///     ``Scan`` and ``MeshingService``, used inside the post-capture
    ///     ``ScanPreviewView``.
    public init(
        feedbackProvider: ScanFeedbackProvider? = nil,
        @ViewBuilder overlay: @escaping (ScanningSession) -> Overlay,
        @ViewBuilder previewControls: @escaping (Scan, MeshingService) -> PreviewControls
    ) {
        self.feedbackProvider = feedbackProvider
        self.overlay = overlay
        self.previewControls = previewControls
    }

    public var body: some View {
        ZStack {
            MetalLayerView(session: session, device: metalDevice)
                .ignoresSafeArea()

            overlay(session)
        }
        .ignoresSafeArea()
        .onAppear {
            session.feedbackProvider = feedbackProvider
            session.configure(scanStore: scanStore)
            session.startSession()
        }
        .onDisappear {
            session.stopSession()
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
