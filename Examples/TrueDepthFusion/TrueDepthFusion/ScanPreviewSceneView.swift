//
//  ScanPreviewSceneView.swift

import SceneKit
import SwiftUI
import TrueDepthFusionObjC

/// UIViewRepresentable wrapper around SCNView.
/// Uses UIViewRepresentable (not SwiftUI's SceneView) to preserve
/// snapshot() and direct SCNNode mutation (RK-14 pattern).
struct ScanPreviewSceneView: UIViewRepresentable {
    let scan: Scan?
    let mesh: SCMesh?
    /// Called once the view is ready with the current SCNView for snapshot.
    var onViewReady: ((SCNView) -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = UIColor(white: 0.14, alpha: 1)
        sceneView.allowsCameraControl = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = true

        // Load the bundled .scn file which carries the camera (pointOfView)
        if let scene = SCNScene(named: "ScanPreviewViewController.scn") {
            sceneView.scene = scene
        } else {
            sceneView.scene = SCNScene()
        }

        context.coordinator.sceneView = sceneView
        context.coordinator.initialPointOfView = sceneView.pointOfView?.transform ?? SCNMatrix4Identity

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        let coordinator = context.coordinator

        let contentChanged = coordinator.lastScan !== scan || coordinator.lastMesh !== mesh
        guard contentChanged else { return }
        coordinator.lastScan = scan
        coordinator.lastMesh = mesh

        // Reset camera only when the displayed content actually changes
        if let pov = sceneView.pointOfView {
            pov.transform = coordinator.initialPointOfView
        }

        // Remove the previous point cloud / mesh node
        coordinator.pointCloudNode?.removeFromParentNode()
        coordinator.pointCloudNode = nil

        // Add current content node
        let newNode: SCNNode?
        if let mesh = mesh {
            let node = mesh.buildMeshNode()
            node.transform = coordinator.meshTransform ?? SCNMatrix4Identity
            newNode = node
        } else if let scan = scan {
            newNode = scan.pointCloud.buildNode()
        } else {
            newNode = nil
        }

        if let node = newNode {
            node.name = mesh != nil ? "mesh" : "point cloud"
            sceneView.scene?.rootNode.addChildNode(node)
            coordinator.pointCloudNode = node
            // Store transform so mesh inherits point-cloud orientation
            if mesh == nil { coordinator.meshTransform = node.transform }
        }

        // Notify caller so it can snapshot after the view settles
        if let onViewReady {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onViewReady(sceneView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var sceneView: SCNView?
        var pointCloudNode: SCNNode?
        var initialPointOfView: SCNMatrix4 = SCNMatrix4Identity
        var meshTransform: SCNMatrix4?
        weak var lastScan: Scan?
        var lastMesh: SCMesh?
    }
}
