//
//  MetalLayerClient.swift
//
//  Protocol bridge between `MetalLayerView` and the scanning session that
//  owns it. Extracted into its own file so `ScanningSession` can declare
//  conformance before `MetalLayerView.swift` itself migrates into the
//  package (which happens one commit later).
//

#if os(iOS)

import Metal
import QuartzCore

/// Bridge between a `MetalLayerView` and the session/object that wants to
/// drive the layer.
///
/// Conformers (e.g. ``ScanningSession``) receive the hosted `CAMetalLayer`
/// after the UIView is installed and forward tap gestures via
/// ``focusOnTap(at:)``.
///
/// The protocol is `@MainActor`-isolated because every conformer is a
/// SwiftUI-driven `ObservableObject` constructed and mutated on the main
/// actor. Implementors that need to hand the layer off to a background
/// queue (e.g. for the camera-output draw call) should snapshot it into a
/// `nonisolated(unsafe)` property.
@MainActor
public protocol MetalLayerClient: AnyObject {
    var metalLayer: CAMetalLayer? { get set }
    func focusOnTap(at point: CGPoint)
}

#endif
