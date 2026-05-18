//
//  ScanStore.swift

import Foundation
import StandardCyborgCapture

@MainActor
final class ScanStore: ObservableObject {

    @Published private(set) var scans: [Scan] = []

    private let containerURL = URL(fileURLWithPath: NSHomeDirectory().appending("/Documents"))

    init() {
        reload()
    }

    func reload() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }

        let plyURLs = urls
            .filter { $0.pathExtension == "ply" }
            .filter { !$0.lastPathComponent.contains("-mesh") }

        scans = plyURLs
            .map { Scan(plyPath: $0.path) }
            .sorted { $0.dateCreated.compare($1.dateCreated) == .orderedDescending }
    }

    func add(_ scan: Scan) {
        guard scan.plyPath == nil else { return }
        do {
            try scan.write(toContainerPath: containerURL.path)
            scans.insert(scan, at: 0)
        } catch {
            print("Error saving scan: \(error)")
        }
    }

    func remove(_ scan: Scan) {
        guard let index = scans.firstIndex(of: scan) else { return }
        do {
            try scan.deleteFiles()
            scans.remove(at: index)
        } catch {
            print("Error deleting scan files: \(error)")
        }
    }

    func createBPLYScanDirectory() -> String {
        let directoryName = Scan.string(from: Date())
        let absoluteDirectory = containerURL.appendingPathComponent(directoryName)
        try? FileManager.default.createDirectory(at: absoluteDirectory, withIntermediateDirectories: false, attributes: nil)
        return absoluteDirectory.path
    }
}
