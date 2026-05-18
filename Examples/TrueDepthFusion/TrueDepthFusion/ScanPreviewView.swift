//
//  ScanPreviewView.swift

import ModelIO
import SceneKit
import StandardCyborgFusion
import SwiftUI
import TrueDepthFusionObjC

struct ScanPreviewView: View {
    @EnvironmentObject private var scanStore: ScanStore
    @Environment(\.dismiss) private var dismiss

    let scan: Scan

    @StateObject private var meshingService = MeshingService()

    @State private var showJetsonSettings = false
    @State private var showNamePrompt = false
    @State private var pendingExportMode: ExportMode?
    @State private var sceneViewRef: SCNView?

    var body: some View {
        ZStack(alignment: .top) {
            ScanPreviewSceneView(
                scan: scan,
                mesh: meshingService.mesh,
                onViewReady: { scnView in
                    sceneViewRef = scnView
                    // Snapshot for thumbnail if not yet captured
                    if scan.thumbnail == nil {
                        let snapshot = scnView.snapshot()
                        scan.thumbnail = snapshot.resized(toWidth: 640)
                    }
                }
            )
            .ignoresSafeArea()

            // Meshing progress overlay
            if meshingService.isRunning {
                VStack(spacing: 12) {
                    ProgressView(value: meshingService.progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 40)
                    Button("Cancel") {
                        meshingService.cancelMeshing()
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground).opacity(0.8))
                    .cornerRadius(8)
                }
                .padding(.top, 120)
                .transition(.opacity)
            }

            // Top-bar controls
            HStack(alignment: .top) {
                Button(role: .destructive) {
                    scanStore.remove(scan)
                    dismiss()
                } label: {
                    Text("DELETE")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                .padding(.leading, 20)
                .padding(.top, 60)

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        showNamePrompt = true
                        pendingExportMode = .share
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.blue)
                            .frame(width: 27, height: 27)
                    }

                    Button {
                        showJetsonSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.blue)
                            .frame(width: 27, height: 27)
                    }
                }
                .padding(.trailing, 20)
                .padding(.top, 60)
            }

            // Bottom controls
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if !meshingService.isRunning {
                            Button {
                                if meshingService.mesh != nil {
                                    // Already meshed — export options
                                    showNamePrompt = true
                                    pendingExportMode = .share
                                } else {
                                    meshingService.runMeshing(on: scan)
                                }
                            } label: {
                                Text(meshingService.mesh != nil ? "Mesh Ready" : "Run Meshing")
                                    .font(.body)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.blue, lineWidth: 1)
                                    )
                            }

                            Button("Done") { dismiss() }
                                .padding(.bottom, 4)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 40)
            }
        }
        // Name prompt sheet
        .sheet(isPresented: $showNamePrompt) {
            if let mode = pendingExportMode {
                ExportNamePromptView(scan: scan, mesh: meshingService.mesh, mode: mode, sceneView: sceneViewRef)
            }
        }
        .sheet(isPresented: $showJetsonSettings) {
            JetsonSettingsView()
        }
    }
}

// MARK: - ExportMode

enum ExportMode {
    case share
    case jetson
}

// MARK: - ExportNamePromptView

private struct ExportNamePromptView: View {
    let scan: Scan
    let mesh: SCMesh?
    let mode: ExportMode
    let sceneView: SCNView?

    @State private var name: String = ""
    @State private var isWorking = false
    @State private var shareItems: [Any]?
    @Environment(\.dismiss) private var dismiss

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
        let namePrefix = Self.sanitize(name)
        switch mode {
        case .share:
            await performShare(namePrefix: namePrefix)
        case .jetson:
            await performJetson(namePrefix: namePrefix)
        }
    }

    private func performShare(namePrefix: String) async {
        let url: URL?
        if let mesh = mesh {
            let filename = Self.outputFilename(name: namePrefix)
            let path = NSTemporaryDirectory() + filename
            try? FileManager.default.removeItem(atPath: path)
            mesh.writeToPLY(atPath: path)
            url = URL(fileURLWithPath: path)
        } else {
            url = Self.compressedPLY(for: scan, namePrefix: namePrefix)
        }
        if let url {
            await MainActor.run { shareItems = [url] }
        }
    }

    private func performJetson(namePrefix: String) async {
        let plyURL: URL
        if let mesh = mesh {
            let filename = Self.outputFilename(name: namePrefix)
            let path = NSTemporaryDirectory() + filename
            try? FileManager.default.removeItem(atPath: path)
            mesh.writeToPLY(atPath: path)
            plyURL = URL(fileURLWithPath: path)
        } else if let plyPath = scan.plyPath {
            let renamed = NSTemporaryDirectory() + Self.outputFilename(name: namePrefix)
            try? FileManager.default.removeItem(atPath: renamed)
            try? FileManager.default.copyItem(atPath: plyPath, toPath: renamed)
            plyURL = URL(fileURLWithPath: renamed)
        } else {
            return
        }

        JetsonUploader.upload(plyFileURL: plyURL) { result in
            Task { @MainActor in
                if let vc = UIApplication.shared.topViewController() {
                    JetsonUploader.showResult(result, from: vc)
                }
            }
        }
        dismiss()
    }

    private static func sanitize(_ input: String) -> String {
        let under = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(under.unicodeScalars.filter { allowed.contains($0) })
    }

    private static func outputFilename(name: String) -> String {
        if name.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd--HH-mm-ss"
            return "model_\(f.string(from: Date())).ply"
        }
        return "model_\(name).ply"
    }

    private static func compressedPLY(for scan: Scan, namePrefix: String) -> URL? {
        let url = scan.writeCompressedPLY()
        let renamed = url.deletingLastPathComponent()
            .appendingPathComponent(outputFilename(name: namePrefix))
        try? FileManager.default.removeItem(at: renamed)
        try? FileManager.default.copyItem(at: url, to: renamed)
        return renamed
    }
}

// MARK: - SharePayload (Identifiable wrapper for sheet)

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - UIApplication helper

private extension UIApplication {
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
        if let nav = root as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = root as? UITabBarController { return topViewController(base: tab.selectedViewController) }
        if let presented = root?.presentedViewController { return topViewController(base: presented) }
        return root
    }
}
