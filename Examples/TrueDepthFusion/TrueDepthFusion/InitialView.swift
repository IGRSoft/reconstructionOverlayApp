//
//  InitialView.swift

import SwiftUI
import UIKit  // needed for UIDevice.current.localizedModel

struct InitialView: View {
    @EnvironmentObject var scanStore: ScanStore
    @State private var fullScreen: FullScreenDestination?
    @State private var navigationPath = NavigationPath()

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
                ScanningView()
                    .environmentObject(scanStore)
                    .ignoresSafeArea()
            case .bplyScanning:
                BPLYScanningView()
                    .environmentObject(scanStore)
                    .ignoresSafeArea()
            }
        }
    }
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

