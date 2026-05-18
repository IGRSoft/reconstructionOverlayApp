//
//  ScanStore.swift

#if os(iOS)

import Foundation
import StandardCyborgCaptureObjC

/// SwiftUI-friendly directory listing of persisted `Scan` files in the
/// host app's `Documents/` folder.
///
/// Manages add/remove/reload of `.ply` files; thumbnails are written and
/// loaded by the underlying `Scan` ObjC++ type.
@MainActor
public final class ScanStore: ObservableObject {

    @Published public private(set) var scans: [Scan] = []

    private let containerURL = URL(fileURLWithPath: NSHomeDirectory().appending("/Documents"))

    public init() {
        reload()
    }

    public func reload() {
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

    public func add(_ scan: Scan) {
        guard scan.plyPath == nil else { return }
        do {
            try scan.write(toContainerPath: containerURL.path)
            scans.insert(scan, at: 0)
        } catch {
            print("Error saving scan: \(error)")
        }
    }

    public func remove(_ scan: Scan) {
        guard let index = scans.firstIndex(of: scan) else { return }
        do {
            try scan.deleteFiles()
            scans.remove(at: index)
        } catch {
            print("Error deleting scan files: \(error)")
        }
    }

    public func createBPLYScanDirectory() -> String {
        let directoryName = Scan.string(from: Date())
        let absoluteDirectory = containerURL.appendingPathComponent(directoryName)
        try? FileManager.default.createDirectory(at: absoluteDirectory, withIntermediateDirectories: false, attributes: nil)
        return absoluteDirectory.path
    }
}

#endif
