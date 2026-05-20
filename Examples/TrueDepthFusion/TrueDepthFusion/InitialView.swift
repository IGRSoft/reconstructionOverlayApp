//
//  InitialView.swift

import StandardCyborgCapture
import StandardCyborgFusion
import SwiftUI
import UIKit  // needed for UIDevice.current.localizedModel

struct InitialView: View {
    @EnvironmentObject var scanStore: ScanStore
    @State private var fullScreen: FullScreenDestination?
    @State private var navigationPath = NavigationPath()

    @State private var bplyShareItems: [Any]?
    @State private var pendingBPLYItems: [Any]?

    private var scanningConfiguration: ScanningConfiguration {
        let d = UserDefaults.standard
        let config = ScanningConfiguration(
            tapToStartStop: d.bool(forKey: "tap_to_start_stop"),
            useFullResolutionDepthFrames: d.bool(forKey: "full_resolution_depth_frames", defaultValue: false),
            stopScanOnReconstructionFailure: d.bool(forKey: "stop_scanning_on_reconstruction_failure", defaultValue: true),
            maxICPIterations: Int32(d.integer(forKey: "icp_max_iteration_count")),
            icpTolerance: d.float(forKey: "icp_tolerance"),
            bplyExportEnabled: d.bool(forKey: "dump_raw_frames_to_bply", defaultValue: false)
        )
        return config
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 32) {
                Spacer()

                Text("Welcome to Overlay Vision on \(UIDevice.current.localizedModel)")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button(action: {
                    fullScreen = .scanning
                }) {
                    Text("SCAN")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.horizontal, 40)
                }

                NavigationLink(value: Route.scansList) {
                    Text("View Scans")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .padding(.horizontal, 40)
                }

                Spacer()
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .scansList:
                    ScansListView()
                }
            }
        }
        .fullScreenCover(item: $fullScreen, onDismiss: {
            if let items = pendingBPLYItems {
                bplyShareItems = items
                pendingBPLYItems = nil
            }
        }) { _ in
            ScanningContainerView(
                configuration: scanningConfiguration,
                onBPLYExport: { url in
                    pendingBPLYItems = [url]
                    fullScreen = nil
                },
                onDone: { fullScreen = nil }
            )
            .environmentObject(scanStore)
            .ignoresSafeArea()
        }
        .sheet(item: Binding(
            get: { bplyShareItems.map { BPLYShare(items: $0) } },
            set: { if $0 == nil { bplyShareItems = nil } }
        )) { payload in
            ActivityView(activityItems: payload.items, applicationActivities: nil)
                .ignoresSafeArea()
        }
    }
}

private struct ScanningContainerView: View {
    @EnvironmentObject var scanStore: ScanStore
    let configuration: ScanningConfiguration
    let onBPLYExport: ((URL) -> Void)?
    let onDone: () -> Void

    @State private var previewScan: ScanSelection?

    var body: some View {
        ScanningView(configuration: configuration, feedbackProvider: AudioAndHapticEngine.shared, onBPLYExport: onBPLYExport) { session in
            FaceOvalOverlay(isScanning: session.scanning)
                .allowsHitTesting(false)
                .frame(maxHeight: 600)
                .padding(.vertical, 20)

            GuidanceLabelsOverlay(
                isPreparing: session.countdownSeconds > 0, isScanning: session.scanning,
                distanceMessage: session.distanceMessage
            )

            ScanControls(
                session: session,
                latestScanThumbnail: session.latestScanThumbnail.map { Image(uiImage: $0) },
                tapToStartStop: configuration.tapToStartStop,
                onShowLatestScan: {
                    if let scan = scanStore.scans.first {
                        previewScan = ScanSelection(scan: scan)
                    }
                },
                onDone: {
                    session.stopSession()
                    onDone()
                }
            )
        } previewControls: { scan, meshingService in
            ScanPreviewControls(scan: scan, meshingService: meshingService)
        }
        .sheet(item: $previewScan) { selection in
            ScanPreviewView(scan: selection.scan) { scan, meshingService in
                ScanPreviewControls(scan: scan, meshingService: meshingService)
            }
            .environmentObject(scanStore)
        }
    }
}

private struct BPLYShare: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - UserDefaults Helper

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if let _ = value(forKey: key) {
            bool(forKey: key)
        } else {
            defaultValue
        }
    }
}
