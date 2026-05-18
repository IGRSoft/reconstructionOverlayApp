//
//  MeshingService.swift

import Foundation
import StandardCyborgFusion
import TrueDepthFusionObjC

// Retroactive Sendable conformance required because SCMesh crosses actor boundaries
// during async meshing. SCMesh is immutable after construction.
extension SCMesh: @retroactive @unchecked Sendable {}

@MainActor
final class MeshingService: ObservableObject {
    @Published private(set) var progress: Float = 0
    @Published private(set) var isRunning = false
    @Published private(set) var mesh: SCMesh?

    private var shouldCancel = false

    func runMeshing(on scan: Scan) {
        guard !isRunning else { return }
        isRunning = true
        shouldCancel = false
        progress = 0
        mesh = nil

        let parameters = SCMeshingParameters()
        parameters.resolution = 5
        parameters.smoothness = 1
        parameters.surfaceTrimmingAmount = 5
        parameters.closed = true

        scan.meshTexturing.reconstructMesh(
            pointCloud: scan.pointCloud,
            textureResolution: 2048,
            meshingParameters: parameters,
            coloringStrategy: .vertex,
            progress: { [weak self] pct, shouldStop in
                guard let self else { return }
                DispatchQueue.main.async { self.progress = pct }
                shouldStop.pointee = ObjCBool(self.shouldCancel)
            },
            completion: { [weak self] _, scMesh in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isRunning = false
                    self.shouldCancel = false
                    if let scMesh { self.mesh = scMesh }
                }
            }
        )
    }

    func cancelMeshing() {
        shouldCancel = true
    }
}
