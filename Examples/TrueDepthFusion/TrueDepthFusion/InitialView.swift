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

    private var isBPLYMode: Bool {
        UserDefaults.standard.bool(forKey: "dump_raw_frames_to_bply", defaultValue: false)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 32) {
                Spacer()

                Text("Welcome to Overlay Vision on \(UIDevice.current.localizedModel)")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button(action: {
                    fullScreen = isBPLYMode ? .bplyScanning : .scanning
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
        .fullScreenCover(item: $fullScreen) { destination in
            switch destination {
            case .scanning:
                ScanningContainerView {
                    fullScreen = nil
                }
                .environmentObject(scanStore)
                .ignoresSafeArea()
            case .bplyScanning:
                BPLYScanningView(
                    feedbackProvider: AudioAndHapticEngine.shared,
                    onExport: { bplyShareItems = [$0] },
                    onDone: { fullScreen = nil }
                )
                .environmentObject(scanStore)
                .ignoresSafeArea()
            }
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
    let onDone: () -> Void

    @State private var previewScan: ScanSelection?

    var body: some View {
        ScanningView(feedbackProvider: AudioAndHapticEngine.shared) { session in
            FaceOvalOverlay(isScanning: session.scanning)
                .allowsHitTesting(false)
                .frame(maxHeight: 600)
                .padding(.vertical, 20)

            GuidanceLabelsOverlay(
                isScanning: session.scanning,
                distanceMessage: session.distanceMessage
            )

            ScanControls(
                session: session,
                latestScanThumbnail: session.latestScanThumbnail.map { Image(uiImage: $0) },
                tapToStartStop: UserDefaults.standard.bool(forKey: "tap_to_start_stop"),
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
        if let defaultNumber = object(forKey: key) as? NSNumber {
            return defaultNumber.boolValue
        } else {
            return defaultValue
        }
    }
}
