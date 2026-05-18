// ScanStoreTests.swift

import Testing
import Foundation
@testable import TrueDepthFusion

@MainActor
@Suite("ScanStore")
struct ScanStoreTests {

    // MARK: - createBPLYScanDirectory

    @Test("createBPLYScanDirectory returns a path inside Documents")
    func bplyDirectoryIsInsideDocuments() async {
        let store = ScanStore()
        let path = store.createBPLYScanDirectory()

        let documentsPath = NSHomeDirectory().appending("/Documents")
        #expect(path.hasPrefix(documentsPath), "Expected path inside Documents, got: \(path)")

        // Clean up
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test("createBPLYScanDirectory creates the directory on disk")
    func bplyDirectoryIsCreated() async {
        let store = ScanStore()
        let path = store.createBPLYScanDirectory()

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        #expect(exists && isDirectory.boolValue, "Directory should exist at: \(path)")

        // Clean up
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test("Two consecutive createBPLYScanDirectory calls return distinct paths")
    func bplyDirectoryIsUnique() async throws {
        let store = ScanStore()
        let path1 = store.createBPLYScanDirectory()
        // Sleep 1 s so the date-based name differs
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let path2 = store.createBPLYScanDirectory()

        #expect(path1 != path2, "Each scan directory should have a unique timestamp-based name")

        // Clean up
        try? FileManager.default.removeItem(atPath: path1)
        try? FileManager.default.removeItem(atPath: path2)
    }

    // MARK: - Initial state

    @Test("ScanStore starts with empty or pre-existing scans without crashing")
    func initialStateNoCrash() async {
        let store = ScanStore()
        // We only assert it does not throw — the actual count depends on simulator state.
        _ = store.scans
    }
}
