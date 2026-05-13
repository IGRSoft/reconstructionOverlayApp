//
//  ScansViewController.swift
//  DepthRenderer
//


import Foundation
import UIKit

@MainActor
final class ScansViewController: UITableViewController {
    
    // MARK: - UIViewController
    
    override func awakeFromNib() {
        super.awakeFromNib()

        tableView.addSubview(_noScansLabel)
        _noScansLabel.text = "No Scans"
        _noScansLabel.textAlignment = NSTextAlignment.center
        _noScansLabel.textColor = UIColor.gray
        _noScansLabel.font = UIFont.systemFont(ofSize: 24, weight: UIFont.Weight.medium)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let settingsButton = UIBarButtonItem(image: UIImage(systemName: "gear"),
                                             style: .plain,
                                             target: self,
                                             action: #selector(_showJetsonSettings))
        navigationItem.rightBarButtonItem = settingsButton
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        _scans = _appDelegate.scans
        
        _updateNoScansLabel()
        tableView.reloadData()
        
        navigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: true)
    }
    
    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return _scans.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let scan = _scans[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "ScanPreviewCell", for: indexPath) as! ScanPreviewCell
        cell.thumbnailView.image = scan.thumbnail
        cell.dateLabel.text = ScansViewController._dateFormatter.string(from: scan.dateCreated)
        cell.timeLabel.text = ScansViewController._timeFormatter.string(from: scan.dateCreated)
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        _scanPreviewViewController.scan = _scans[indexPath.row]
        present(_scanPreviewViewController, animated: true, completion: nil)
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { action, view, completion in
            self._deleteScan(at: indexPath)
            completion(true)
        }

        let export = UIContextualAction(style: .normal, title: "Export") { action, view, completion in
            let scan = self._scans[indexPath.row]
            self._export(scan)
            completion(true)
        }

        let jetson = UIContextualAction(style: .normal, title: "Send to Robot") { action, view, completion in
            let scan = self._scans[indexPath.row]
            self._sendToJetson(scan)
            completion(true)
        }
        jetson.backgroundColor = .systemIndigo

        return UISwipeActionsConfiguration(actions: [delete, export, jetson])
    }
    
    // MARK: - Private
    
    private static let _dateFormatter: DateFormatter = {
        var formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    private static let _timeFormatter: DateFormatter = {
        var formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    private let _appDelegate = UIApplication.shared.delegate! as! AppDelegate
    private let _noScansLabel = UILabel()
    private var _scans: [Scan] = []
    
    private lazy var _scanPreviewViewController: ScanPreviewViewController = {
        let scanVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "ScanPreviewViewController") as! ScanPreviewViewController
        scanVC.deletionHandler = { [unowned self, scanVC] in
            self._appDelegate.remove(scanVC.scan!)
            self.dismiss(animated: true, completion: nil)
        }
        scanVC.doneHandler = { [unowned self] in
            self.dismiss(animated: true, completion: nil)
        }
        
        return scanVC
    }()
    
    private func _export(_ scan: Scan) {
        guard scan.plyPath != nil else { return }
        _promptForName { [weak self] namePrefix in
            guard let self = self else { return }
            let baseURL = scan.writeCompressedPLY()
            let renamedURL = baseURL.deletingLastPathComponent().appendingPathComponent(ScansViewController._outputFilename(name: namePrefix))
            try? FileManager.default.removeItem(at: renamedURL)
            try? FileManager.default.copyItem(at: baseURL, to: renamedURL)
            let controller = UIActivityViewController(activityItems: [renamedURL], applicationActivities: nil)
            if let popoverController = controller.popoverPresentationController,
               let scanIndex = self._scans.firstIndex(of: scan)
            {
                popoverController.sourceView = self.tableView.cellForRow(at: IndexPath(row: scanIndex, section: 0))?.contentView
            }
            self.present(controller, animated: true)
        }
    }
    
    @objc private func _showJetsonSettings() {
        JetsonUploader.showSettings(from: self)
    }

    private func _sendToJetson(_ scan: Scan) {
        guard let plyPath = scan.plyPath else { return }
        _promptForName { [weak self] namePrefix in
            guard let self = self else { return }
            let renamedPath = NSTemporaryDirectory().appending("/\(ScansViewController._outputFilename(name: namePrefix))")
            try? FileManager.default.removeItem(atPath: renamedPath)
            try? FileManager.default.copyItem(atPath: plyPath, toPath: renamedPath)
            JetsonUploader.upload(plyFileURL: URL(fileURLWithPath: renamedPath)) { [weak self] result in
                guard let self = self else { return }
                JetsonUploader.showResult(result, from: self)
            }
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
            completion(ScansViewController._sanitizeNamePrefix(raw))
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

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

    private func _deleteScan(at indexPath: IndexPath) {
        let scan = _scans[indexPath.row]
        
         _appDelegate.remove(scan)
        
        tableView.beginUpdates()
        tableView.deleteRows(at: [indexPath], with: .automatic)
        _scans.remove(at: indexPath.row)
        tableView.endUpdates()
        
        _updateNoScansLabel()
    }
    
    private func _updateNoScansLabel() {
        _noScansLabel.isHidden = _scans.count > 0
        
        if _noScansLabel.isHidden == false {
            _noScansLabel.frame = UIScreen.main.bounds.offsetBy(dx: 0, dy: 0.5 * tableView.rowHeight - 88 - 0.5 * _noScansLabel.font.lineHeight)
        }
    }
    
}

class ScanPreviewCell: UITableViewCell {
    
    @IBOutlet weak var thumbnailView: UIImageView!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    
}
