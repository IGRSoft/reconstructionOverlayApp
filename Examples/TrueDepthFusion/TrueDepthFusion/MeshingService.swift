//
//  MeshingService.swift

import Foundation
import os
import StandardCyborgFusion
import StandardCyborgCapture

// Retroactive Sendable conformance required because SCMesh crosses actor boundaries
// during async meshing. SCMesh is immutable after construction.
extension SCMesh: @retroactive @unchecked Sendable {}

@MainActor
final class MeshingService: ObservableObject {
    @Published private(set) var progress: Float = 0
    @Published private(set) var isRunning = false
    @Published private(set) var mesh: SCMesh?

    // Lock-protected so the SDK's background progress callback can read it
    // without crossing the @MainActor isolation boundary.
    private let cancelFlag = OSAllocatedUnfairLock(initialState: false)

    func runMeshing(on scan: Scan) {
        guard !isRunning else { return }
        isRunning = true
        cancelFlag.withLock { $0 = false }
        progress = 0
        mesh = nil

        let parameters = SCMeshingParameters()
        parameters.resolution = 5
        parameters.smoothness = 1
        parameters.surfaceTrimmingAmount = 5
        parameters.closed = true

        let cancelFlag = self.cancelFlag

        // The closures below must be explicitly @Sendable to opt out of Swift 6's
        // closure actor-isolation inheritance (SE-0420). Without @Sendable they
        // would inherit @MainActor from the enclosing method and trap with
        // EXC_BREAKPOINT when the SDK invokes them on its _reconstructionQueue.
        scan.meshTexturing.reconstructMesh(
            pointCloud: scan.pointCloud,
            textureResolution: 2048,
            meshingParameters: parameters,
            coloringStrategy: .vertex,
            progress: { @Sendable [weak self] pct, shouldStop in
                shouldStop.pointee = ObjCBool(cancelFlag.withLock { $0 })
                Task { @MainActor in self?.progress = pct }
            },
            completion: { @Sendable [weak self] _, scMesh in
                Task { @MainActor in
                    guard let self else { return }
                    self.isRunning = false
                    cancelFlag.withLock { $0 = false }
                    if let scMesh { self.mesh = scMesh }
                }
            }
        )
    }

    func cancelMeshing() {
        cancelFlag.withLock { $0 = true }
    }
}
