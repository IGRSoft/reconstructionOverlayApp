//
//  ScanningView.swift

import Metal
import SwiftUI
import TrueDepthFusionObjC

struct ScanningView: View {
    @EnvironmentObject private var scanStore: ScanStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session = ScanningSession()
    @State private var showLatestScan: ScanSelection? = nil

    private let metalDevice = MTLCreateSystemDefaultDevice()!

    var body: some View {
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
                latestScanThumbnail: session.latestScanThumbnail,
                onShowLatestScan: {
                    if let scan = scanStore.scans.first {
                        showLatestScan = ScanSelection(scan: scan)
                    }
                },
                onDone: {
                    session.stopSession()
                    dismiss()
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
            ScanPreviewView(scan: selection.scan)
                .environmentObject(scanStore)
        }
        // Show latest existing scan from the list
        .sheet(item: $showLatestScan) { selection in
            ScanPreviewView(scan: selection.scan)
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
