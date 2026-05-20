//
//  ScanPreviewView.swift

#if os(iOS)

import SceneKit
import StandardCyborgCaptureObjC
import StandardCyborgFusion
import SwiftUI

/// SwiftUI preview of a captured ``Scan``: renders the point cloud (and the
/// reconstructed mesh once meshing finishes) with consumer-provided controls
/// layered on top.
///
/// The ``MeshingService`` is owned internally and passed to the controls
/// builder so the consumer can wire meshing actions and progress display.
public struct ScanPreviewView<Controls: View>: View {
    public let scan: Scan
    @StateObject private var meshingService = MeshingService()
    @State private var sceneViewRef: SCNView?
    private let controls: (Scan, MeshingService) -> Controls

    public init(
        scan: Scan,
        @ViewBuilder controls: @escaping (Scan, MeshingService) -> Controls
    ) {
        self.scan = scan
        self.controls = controls
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ScanPreviewSceneView(
                scan: scan,
                mesh: meshingService.mesh,
                onViewReady: { scnView in
                    sceneViewRef = scnView
                    if scan.thumbnail == nil {
                        let snapshot = scnView.snapshot()
                        scan.thumbnail = snapshot.resized(toWidth: 640)
                    }
                }
            )
            .ignoresSafeArea()

            controls(scan, meshingService)
        }
    }
}

#endif
