//
//  MetalLayerView.swift
//
//  UIViewRepresentable that hosts a CAMetalLayer and exposes it to ScanningSession.
//  Tap gesture is forwarded to ScanningSession.focusOnTap(at:).

import Metal
import SwiftUI
import UIKit

struct MetalLayerView: UIViewRepresentable {
    let session: ScanningSession
    let device: MTLDevice

    func makeUIView(context: Context) -> _MetalHostView {
        let view = _MetalHostView()
        view.backgroundColor = .black

        let metalLayer = CAMetalLayer()
        metalLayer.isOpaque = true
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        view.metalLayer = metalLayer
        view.layer.addSublayer(metalLayer)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        // Expose to session on next runloop tick after layout
        context.coordinator.metalLayer = metalLayer
        DispatchQueue.main.async {
            session.metalLayer = metalLayer
        }

        return view
    }

    func updateUIView(_ uiView: _MetalHostView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let session: ScanningSession
        var metalLayer: CAMetalLayer?

        init(session: ScanningSession) { self.session = session }

        @MainActor @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            session.focusOnTap(at: location)
        }
    }
}

// MARK: - Host UIView

final class _MetalHostView: UIView {
    var metalLayer: CAMetalLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let metalLayer else { return }
        CATransaction.begin()
        CATransaction.disableActions()
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )
        CATransaction.commit()
    }
}
