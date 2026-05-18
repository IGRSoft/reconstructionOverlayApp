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
/// ``MetalLayerView`` + ``FaceOvalOverlay`` + ``ScanControls`` HUD. When the
/// session produces a completed scan, the view internally presents a
/// ``ScanPreviewView`` via `.fullScreenCover` and forwards the host-supplied
/// `onExport` / `onShowSettings` closures into that preview.
///
/// Inject a ``ScanStore`` via `.environmentObject(...)` before presentation.
public struct ScanningView: View {
    @EnvironmentObject private var scanStore: ScanStore

    @StateObject private var session = ScanningSession()
    @State private var showLatestScan: ScanSelection? = nil

    private let onDone: () -> Void
    private let onShowLatestScan: () -> Void
    private let onExport: (Scan, SCMesh?) -> Void
    private let onShowSettings: () -> Void

    private let metalDevice = MTLCreateSystemDefaultDevice()!

    /// - Parameters:
    ///   - onExport: Forwarded into ``ScanPreviewView`` when the user
    ///     taps Share inside the post-capture preview.
    ///   - onShowSettings: Forwarded into ``ScanPreviewView`` for the
    ///     gear button in the preview's top-right.
    ///   - onDone: Called when the user dismisses the scanning view
    ///     (the consumer typically pops a sheet or navigation route).
    ///   - onShowLatestScan: Called when the user taps the latest-scan
    ///     thumbnail in the HUD. The consumer is responsible for
    ///     presenting a ``ScanPreviewView`` for ``ScanStore``'s first
    ///     scan.
    public init(
        onExport: @escaping (Scan, SCMesh?) -> Void,
        onShowSettings: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onShowLatestScan: @escaping () -> Void
    ) {
        self.onExport = onExport
        self.onShowSettings = onShowSettings
        self.onDone = onDone
        self.onShowLatestScan = onShowLatestScan
    }

    public var body: some View {
        ZStack {
            // Metal rendering layer (full screen)
            MetalLayerView(session: session, device: metalDevice)
                .ignoresSafeArea()

            // Face oval guide
            FaceOvalOverlay(isScanning: session.scanning)
                .allowsHitTesting(false)
                .frame(maxHeight: 600)
                .padding(.vertical, 20)

            // Guidance labels
            guidanceLabels

            // HUD controls
            ScanControls(
                session: session,
                latestScanThumbnail: session.latestScanThumbnail.map { Image(uiImage: $0) },
                tapToStartStop: UserDefaults.standard.bool(forKey: "tap_to_start_stop"),
                onShowLatestScan: onShowLatestScan,
                onDone: {
                    session.stopSession()
                    onDone()
                }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            session.configure(scanStore: scanStore)
            session.startSession()
        }
        .onDisappear {
            session.stopSession()
        }
        // Present scan preview when a scan completes — bind directly to
        // session.completedScan as the single source of truth.
        .fullScreenCover(item: Binding(
            get: { session.completedScan.map { ScanSelection(scan: $0) } },
            set: { if $0 == nil { session.dismissCompleted() } }
        )) { selection in
            ScanPreviewView(
                scan: selection.scan,
                onExport: onExport,
                onShowSettings: onShowSettings
            )
            .environmentObject(scanStore)
        }
    }

    @ViewBuilder
    private var guidanceLabels: some View {
        GeometryReader { proxy in
            let ovalH = proxy.size.height * 0.72
            let ovalTop = (proxy.size.height - ovalH) / 2
            let centerY = ovalTop + ovalH / 2

            if !session.scanning {
                VStack(spacing: 10) {
                    Text("Center your face\nin the oval")
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(10)
                        .opacity(session.scanning ? 0 : 1)
                        .animation(.easeInOut(duration: 0.4), value: session.scanning)

                    if let msg = session.distanceMessage {
                        Text(msg)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.45))
                            .cornerRadius(10)
                    }
                }
                .frame(maxWidth: 200)
                .position(x: proxy.size.width / 2, y: centerY)
            }
        }
        .allowsHitTesting(false)
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
