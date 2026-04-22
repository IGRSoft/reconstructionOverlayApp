//
//  ScanPreviewViewController.swift
//  DepthRenderer
//


import Foundation
import ModelIO
import QuickLook
import StandardCyborgFusion
import SceneKit
import UIKit

class ScanPreviewViewController: UIViewController, QLPreviewControllerDataSource {
    
    // MARK: - IB Outlets and Actions
    
    @IBOutlet private weak var sceneView: SCNView!
    @IBOutlet private weak var meshButton: UIButton!
    @IBOutlet private weak var meshingProgressContainer: UIView!
    @IBOutlet private weak var meshingProgressView: UIProgressView!
    private var _quickLookUSDZURL: URL?
    
    @IBAction private func _export(_ sender: AnyObject) {
        guard scan != nil else { return }

        _promptForName { [weak self] namePrefix in
            guard let self = self else { return }

            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

            sheet.addAction(UIAlertAction(title: "Send to Jetson", style: .default) { [weak self] _ in
                self?._sendToJetson(namePrefix: namePrefix)
            })

            sheet.addAction(UIAlertAction(title: "Share / Export", style: .default) { [weak self] _ in
                self?._share(sender: sender, namePrefix: namePrefix)
            })

            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

            if let popover = sheet.popoverPresentationController {
                popover.sourceView = sender as? UIView ?? self.view
            }

            self.present(sheet, animated: true)
        }
    }

    private func _share(sender: AnyObject, namePrefix: String) {
        guard let scan = scan else { return }
        let shareURL: URL?

        if _shouldExportToUSDZ {
            if let mesh = _mesh {
                let filename = ScanPreviewViewController._prefixedFilename("mesh.ply", prefix: namePrefix)
                let tempPLYPath = NSTemporaryDirectory().appending("/\(filename)")
                try? FileManager.default.removeItem(atPath: tempPLYPath)
                mesh.writeToPLY(atPath: tempPLYPath)
                shareURL = URL(fileURLWithPath: tempPLYPath)
            } else {
                shareURL = scan.writeUSDZ()
            }
        } else if let meshURL = _meshURL {
            shareURL = meshURL
        } else {
            shareURL = ScanPreviewViewController._compressedPLY(for: scan, namePrefix: namePrefix)
        }

        if let shareURL = shareURL {
            _quickLookUSDZURL = shareURL
            let controller = QLPreviewController()
            controller.dataSource = self
            controller.modalPresentationStyle = .overFullScreen
            self.present(controller, animated: true, completion: nil)
        }
    }

    private func _sendToJetson(namePrefix: String) {
        guard let scan = scan else { return }

        let plyURL: URL

        if let mesh = _mesh {
            let filename = ScanPreviewViewController._prefixedFilename("mesh.ply", prefix: namePrefix)
            let tempPLYPath = NSTemporaryDirectory().appending("/\(filename)")
            try? FileManager.default.removeItem(atPath: tempPLYPath)
            mesh.writeToPLY(atPath: tempPLYPath)
            plyURL = URL(fileURLWithPath: tempPLYPath)
        } else if let plyPath = scan.plyPath {
            if namePrefix.isEmpty {
                plyURL = URL(fileURLWithPath: plyPath)
            } else {
                let originalName = URL(fileURLWithPath: plyPath).lastPathComponent
                let prefixedName = ScanPreviewViewController._prefixedFilename(originalName, prefix: namePrefix)
                let renamedPath = NSTemporaryDirectory().appending("/\(prefixedName)")
                try? FileManager.default.removeItem(atPath: renamedPath)
                try? FileManager.default.copyItem(atPath: plyPath, toPath: renamedPath)
                plyURL = URL(fileURLWithPath: renamedPath)
            }
        } else {
            JetsonUploader.showResult(.failure(NSError(domain: "JetsonUploader", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No PLY data available to send."])), from: self)
            return
        }

        JetsonUploader.upload(plyFileURL: plyURL) { [weak self] result in
            guard let self = self else { return }
            JetsonUploader.showResult(result, from: self)
        }
    }

    // MARK: - Name prompt helpers

    private func _promptForName(completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: "Export", message: "What is your name?", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Leave blank for default filename"
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
            let raw = alert.textFields?.first?.text ?? ""
            completion(ScanPreviewViewController._sanitizeNamePrefix(raw))
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    /// Strips characters that are unsafe in filenames. Spaces become underscores;
    /// anything that is not alphanumeric, a hyphen, or an underscore is removed.
    private static func _sanitizeNamePrefix(_ input: String) -> String {
        let withUnderscores = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(withUnderscores.unicodeScalars.filter { allowed.contains($0) })
    }

    private static func _prefixedFilename(_ filename: String, prefix: String) -> String {
        return prefix.isEmpty ? filename : "\(prefix)-\(filename)"
    }

    /// Writes the scan's compressed PLY to a temp path, renaming it with the given prefix.
    private static func _compressedPLY(for scan: Scan, namePrefix: String) -> URL? {
        let url = scan.writeCompressedPLY()
        guard !namePrefix.isEmpty else { return url }
        let prefixedName = _prefixedFilename(url.lastPathComponent, prefix: namePrefix)
        let renamedURL = url.deletingLastPathComponent().appendingPathComponent(prefixedName)
        try? FileManager.default.removeItem(at: renamedURL)
        try? FileManager.default.copyItem(at: url, to: renamedURL)
        return renamedURL
    }
    
    // MARK: - QLPreviewControllerDataSource
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return _quickLookUSDZURL! as QLPreviewItem
    }
    
    @IBAction private func _delete(_ sender: Any) {
        deletionHandler?()
    }
    
    @IBAction private func _done(_ sender: Any) {
        doneHandler?()
    }
    
    @IBAction private func _runMeshing(_ sender: Any) {
        guard let scan = scan else { return }
        
        meshingProgressContainer.isHidden = false
        meshingProgressContainer.alpha = 0
        meshingProgressView.progress = 0
        UIView.animate(withDuration: 0.4) {
            self.meshingProgressContainer.alpha = 1
        }
        
        let meshingParameters = SCMeshingParameters()
        meshingParameters.resolution = 5
        meshingParameters.smoothness = 1
        meshingParameters.surfaceTrimmingAmount = 5
        meshingParameters.closed = true
        
        let textureResolutionPixels = 2048
        
        scan.meshTexturing.reconstructMesh(
            pointCloud: scan.pointCloud,
            textureResolution: textureResolutionPixels,
            meshingParameters: meshingParameters,
            coloringStrategy: .vertex,
            progress: { percentComplete, shouldStop in
                DispatchQueue.main.async {
                    self.meshingProgressView.progress = percentComplete
                }
                
                shouldStop.pointee = ObjCBool(self._shouldCancelMeshing)
            },
            completion: { error, scMesh in
                if let error = error {
                    print("Meshing error: \(error)")
                }
                
                DispatchQueue.main.async {
                    self.meshingProgressContainer.isHidden = true
                    self._shouldCancelMeshing = false
                    
                    if let mesh = scMesh {
                        let node = mesh.buildMeshNode()
                        node.transform = self._pointCloudNode?.transform ?? SCNMatrix4Identity
                        self._pointCloudNode = node
                        self._mesh = mesh
                    }
                }
            }
        )
    }
    
    @IBAction private func cancelMeshing(_ sender: Any) {
        _shouldCancelMeshing = true
    }
    
    // MARK: - UIViewController
    
    override func viewDidLoad() {
        _initialPointOfView = sceneView.pointOfView!.transform
    }
    
    override func viewWillAppear(_ animated: Bool) {
        sceneView.pointOfView!.transform = _initialPointOfView
        meshButton.isHidden = scan?.plyPath == nil
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if let scan = scan, scan.thumbnail == nil {
            let snapshot = sceneView.snapshot()
            scan.thumbnail = snapshot.resized(toWidth: 640)
        }
    }
    
    // MARK: - Public
    
    var scan: Scan? {
        didSet {
            _pointCloudNode = scan?.pointCloud.buildNode()
        }
    }
    
    var deletionHandler: (() -> Void)?
    var doneHandler: (() -> Void)?
    
    // MARK: - Private
    
    private let _appDelegate = UIApplication.shared.delegate! as! AppDelegate
    private let _shouldExportToUSDZ = true
    private var _shouldCancelMeshing = false
    private var _meshURL: URL?
    private var _mesh: SCMesh?
    private var _initialPointOfView = SCNMatrix4Identity
    private var _pointCloudNode: SCNNode? {
        willSet {
            _pointCloudNode?.removeFromParentNode()
        }
        didSet {
            _pointCloudNode?.name = "point cloud"
            
            // Make sure the view is loaded first
            _ = self.view
            
            if let node = _pointCloudNode {
                sceneView.scene!.rootNode.addChildNode(node)
            }
        }
    }
    
}
