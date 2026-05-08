//
//  ScanPreviewViewController.swift
//  DepthRenderer
//


import Foundation
import ModelIO
import StandardCyborgFusion
import SceneKit
import UIKit

class ScanPreviewViewController: UIViewController {

    // MARK: - IB Outlets and Actions

    @IBOutlet private weak var sceneView: SCNView!
    @IBOutlet private weak var meshButton: UIButton!
    @IBOutlet private weak var meshingProgressContainer: UIView!
    @IBOutlet private weak var meshingProgressView: UIProgressView!
    
    @IBAction private func _export(_ sender: AnyObject) {
        guard scan != nil else { return }

        _promptForName { [weak self] namePrefix in
            guard let self = self else { return }

            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

            sheet.addAction(UIAlertAction(title: "Send to Overlay Robot", style: .default) { [weak self] _ in
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

        if let mesh = _mesh {
            let filename = ScanPreviewViewController._outputFilename(name: namePrefix)
            let tempPLYPath = NSTemporaryDirectory().appending("/\(filename)")
            try? FileManager.default.removeItem(atPath: tempPLYPath)
            mesh.writeToPLY(atPath: tempPLYPath)
            shareURL = URL(fileURLWithPath: tempPLYPath)
        } else {
            shareURL = ScanPreviewViewController._compressedPLY(for: scan, namePrefix: namePrefix)
        }

        if let shareURL = shareURL {
            let controller = UIActivityViewController(activityItems: [shareURL], applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = sender as? UIView ?? self.view
            }
            self.present(controller, animated: true)
        }
    }

    private func _sendToJetson(namePrefix: String) {
        guard let scan = scan else { return }

        let plyURL: URL

        if let mesh = _mesh {
            let filename = ScanPreviewViewController._outputFilename(name: namePrefix)
            let tempPLYPath = NSTemporaryDirectory().appending("/\(filename)")
            try? FileManager.default.removeItem(atPath: tempPLYPath)
            mesh.writeToPLY(atPath: tempPLYPath)
            plyURL = URL(fileURLWithPath: tempPLYPath)
        } else if let plyPath = scan.plyPath {
            let renamedPath = NSTemporaryDirectory().appending("/\(ScanPreviewViewController._outputFilename(name: namePrefix))")
            try? FileManager.default.removeItem(atPath: renamedPath)
            try? FileManager.default.copyItem(atPath: plyPath, toPath: renamedPath)
            plyURL = URL(fileURLWithPath: renamedPath)
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

    private static func _outputFilename(name: String) -> String {
        if name.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd--HH-mm-ss"
            return "model_\(formatter.string(from: Date())).ply"
        }
        return "model_\(name).ply"
    }

    /// Writes the scan's compressed PLY to a temp path, renaming it.
    private static func _compressedPLY(for scan: Scan, namePrefix: String) -> URL? {
        let url = scan.writeCompressedPLY()
        let renamedURL = url.deletingLastPathComponent().appendingPathComponent(_outputFilename(name: namePrefix))
        try? FileManager.default.removeItem(at: renamedURL)
        try? FileManager.default.copyItem(at: url, to: renamedURL)
        return renamedURL
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

                    self.view.bringSubviewToFront(self._gearButton)
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

        _gearButton.setImage(UIImage(systemName: "gear"), for: .normal)
        _gearButton.translatesAutoresizingMaskIntoConstraints = false
        _gearButton.addTarget(self, action: #selector(_showJetsonSettings), for: .touchUpInside)
        view.addSubview(_gearButton)

        // Share button is pinned to safeArea.top and safeArea.trailing-20 with height 27.
        // Gear sits just to the left of share, center-aligned with it.
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            _gearButton.centerYAnchor.constraint(equalTo: safeArea.topAnchor, constant: 13.5),
            _gearButton.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -49),
            _gearButton.widthAnchor.constraint(equalToConstant: 27),
            _gearButton.heightAnchor.constraint(equalToConstant: 27),
        ])

        // Style mesh button to look like a tappable button (matches system blue of share icon)
        meshButton.layer.borderColor = UIColor.systemBlue.cgColor
        meshButton.layer.borderWidth = 1
        meshButton.layer.cornerRadius = 8
        meshButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    }

    @objc private func _showJetsonSettings() {
        JetsonUploader.showSettings(from: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        sceneView.pointOfView!.transform = _initialPointOfView
        meshButton.isHidden = scan == nil
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
    private let _gearButton = UIButton(type: .system)
    private var _shouldCancelMeshing = false
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
