//
//  ExportSheet.swift

import StandardCyborgFusion
import SwiftUI
import TrueDepthFusionObjC
import UIKit

enum ExportTarget: Identifiable {
    case share
    case jetson

    var id: Self { self }
}

struct ExportSheet: View {
    let scan: Scan
    let mesh: SCMesh?
    let target: ExportTarget

    @EnvironmentObject private var scanStore: ScanStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var isWorking = false
    @State private var shareItems: [Any]?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Leave blank for default filename", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        isWorking = true
                        Task {
                            await perform()
                            isWorking = false
                        }
                    }
                    .disabled(isWorking)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { shareItems.map { SharePayload(items: $0) } },
                set: { if $0 == nil { shareItems = nil } }
            )) { payload in
                ActivityView(activityItems: payload.items, applicationActivities: nil)
                    .ignoresSafeArea()
            }
        }
    }

    private func perform() async {
        // Persist the scan before exporting so it appears in the Scans list
        // and any on-disk PLY path is available for use below.
        if scan.plyPath == nil {
            await MainActor.run { scanStore.add(scan) }
        }

        let namePrefix = ExportUtilities.sanitize(name)
        switch target {
        case .share:
            await performShare(namePrefix: namePrefix)
        case .jetson:
            await performJetson(namePrefix: namePrefix)
        }
    }

    private func performShare(namePrefix: String) async {
        let url: URL?
        if scan.plyPath != nil {
            // Prefer the on-disk PLY (post-persist) so we share the saved file.
            url = ExportUtilities.compressedPLY(for: scan, namePrefix: namePrefix)
        } else if let mesh = mesh {
            let filename = ExportUtilities.outputFilename(name: namePrefix)
            let path = NSTemporaryDirectory() + filename
            try? FileManager.default.removeItem(atPath: path)
            mesh.writeToPLY(atPath: path)
            url = URL(fileURLWithPath: path)
        } else {
            url = nil
        }
        if let url {
            await MainActor.run { shareItems = [url] }
        }
    }

    private func performJetson(namePrefix: String) async {
        let plyURL: URL
        if let plyPath = scan.plyPath {
            let renamed = NSTemporaryDirectory() + ExportUtilities.outputFilename(name: namePrefix)
            try? FileManager.default.removeItem(atPath: renamed)
            try? FileManager.default.copyItem(atPath: plyPath, toPath: renamed)
            plyURL = URL(fileURLWithPath: renamed)
        } else if let mesh = mesh {
            let filename = ExportUtilities.outputFilename(name: namePrefix)
            let path = NSTemporaryDirectory() + filename
            try? FileManager.default.removeItem(atPath: path)
            mesh.writeToPLY(atPath: path)
            plyURL = URL(fileURLWithPath: path)
        } else {
            return
        }

        JetsonUploader.upload(plyFileURL: plyURL) { result in
            Task { @MainActor in
                if let vc = ExportUtilities.topViewController() {
                    JetsonUploader.showResult(result, from: vc)
                }
            }
        }
        dismiss()
    }
}

// MARK: - SharePayload

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - ExportUtilities

enum ExportUtilities {
    static func sanitize(_ input: String) -> String {
        let under = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(under.unicodeScalars.filter { allowed.contains($0) })
    }

    static func outputFilename(name: String) -> String {
        if name.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd--HH-mm-ss"
            return "model_\(f.string(from: Date())).ply"
        }
        return "model_\(name).ply"
    }

    static func compressedPLY(for scan: Scan, namePrefix: String) -> URL? {
        let url = scan.writeCompressedPLY()
        let renamed = url.deletingLastPathComponent()
            .appendingPathComponent(outputFilename(name: namePrefix))
        try? FileManager.default.removeItem(at: renamed)
        try? FileManager.default.copyItem(at: url, to: renamed)
        return renamed
    }

    @MainActor
    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
        if let nav = root as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = root as? UITabBarController { return topViewController(base: tab.selectedViewController) }
        if let presented = root?.presentedViewController { return topViewController(base: presented) }
        return root
    }
}
