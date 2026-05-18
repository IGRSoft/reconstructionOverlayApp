//
//  RootView.swift

import SwiftUI
import UIKit

/// Hosts the existing storyboard-driven `InitialViewController` inside SwiftUI.
/// Replaced by a native `NavigationStack { InitialView() }` in Phase 4.
struct RootView: UIViewControllerRepresentable {
    @EnvironmentObject var scanStore: ScanStore

    func makeUIViewController(context: Context) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let nav = storyboard.instantiateInitialViewController()!
        // Walk to the InitialViewController and inject scanStore via a wrapper.
        if let navController = nav as? UINavigationController,
           let initial = navController.viewControllers.first as? InitialViewController {
            initial.scanStore = scanStore
        }
        return nav
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
