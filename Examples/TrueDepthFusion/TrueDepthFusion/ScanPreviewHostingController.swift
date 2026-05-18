//
//  ScanPreviewHostingController.swift
//
//  Transient shim used by ScanningViewController until Phase 7.
//  Exposes the same public interface as the deleted ScanPreviewViewController
//  while the body is now SwiftUI (ScanPreviewView via UIHostingController).

import SwiftUI
import TrueDepthFusionObjC
import UIKit

/// Thin UIViewController that hosts ScanPreviewView.
/// Intentionally mirrors the public API of the deleted ScanPreviewViewController
/// so ScanningViewController (Phase 7) compiles unchanged.
final class ScanPreviewViewController: UIViewController {

    // MARK: - Public API (same as old ScanPreviewViewController)

    var scanStore: ScanStore!
    var deletionHandler: (() -> Void)?
    var doneHandler: (() -> Void)?

    var scan: Scan? {
        didSet { _rebuildHostingController() }
    }

    // MARK: - Private

    private var _hostingController: UIViewController?

    private func _rebuildHostingController() {
        _hostingController?.willMove(toParent: nil)
        _hostingController?.view.removeFromSuperview()
        _hostingController?.removeFromParent()

        guard let scan else { return }

        let inner = _InnerScanPreviewContainer(
            scan: scan,
            scanStore: scanStore,
            deletionHandler: { [weak self] in self?.deletionHandler?() },
            doneHandler: { [weak self] in self?.doneHandler?() }
        )
        let hosting = UIHostingController(rootView: inner)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        _hostingController = hosting
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        _rebuildHostingController()
    }
}

// MARK: - Inner SwiftUI wrapper

private struct _InnerScanPreviewContainer: View {
    let scan: Scan
    let scanStore: ScanStore
    let deletionHandler: () -> Void
    let doneHandler: () -> Void

    var body: some View {
        ScanPreviewView(scan: scan)
            .environmentObject(scanStore)
    }
}
