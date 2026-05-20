//
//  MetalLayerView.swift
//
//  UIViewRepresentable that hosts a CAMetalLayer and exposes it to a
//  MetalLayerClient (e.g. ``ScanningSession``).
//  Tap gesture is forwarded via `focusOnTap(at:)`.

#if os(iOS)

import Metal
import SwiftUI
import UIKit

/// SwiftUI wrapper that owns a `CAMetalLayer` and hands it back to the
/// supplied ``MetalLayerClient`` (e.g. ``ScanningSession``).
public struct MetalLayerView<Client: MetalLayerClient>: UIViewRepresentable {
    public let session: Client
    public let device: MTLDevice

    public init(session: Client, device: MTLDevice) {
        self.session = session
        self.device = device
    }

    public func makeUIView(context: Context) -> MetalHostView {
        let view = MetalHostView()
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

        context.coordinator.metalLayer = metalLayer
        DispatchQueue.main.async {
            session.metalLayer = metalLayer
        }

        return view
    }

    public func updateUIView(_ uiView: MetalHostView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    // MARK: - Coordinator

    public final class Coordinator: NSObject {
        public let session: Client
        var metalLayer: CAMetalLayer?

        public init(session: Client) { self.session = session }

        @MainActor @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            session.focusOnTap(at: location)
        }
    }
}

// MARK: - Host UIView

/// Internal host `UIView` for `CAMetalLayer`. Public consumers do not
/// reference this type directly, but the type itself must be `public`
/// because it appears in the signature of `MetalLayerView.makeUIView`.
public final class MetalHostView: UIView {
    var metalLayer: CAMetalLayer?

    public override func layoutSubviews() {
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

#endif
