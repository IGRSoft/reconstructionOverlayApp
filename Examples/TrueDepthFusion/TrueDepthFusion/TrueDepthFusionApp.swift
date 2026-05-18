//
//  TrueDepthFusionApp.swift

import SwiftUI

@main
struct TrueDepthFusionApp: App {
    @StateObject private var scanStore = ScanStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(scanStore)
                .ignoresSafeArea()
        }
    }
}
