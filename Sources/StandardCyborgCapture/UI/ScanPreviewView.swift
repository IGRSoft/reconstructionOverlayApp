//
//  ScanPreviewView.swift

#if os(iOS)

import ModelIO
import SceneKit
import StandardCyborgFusion
import StandardCyborgCaptureObjC
import SwiftUI

/// SwiftUI preview of a captured ``Scan``: renders the point cloud (and the
/// reconstructed mesh once meshing finishes) and exposes Share/Settings
/// hooks via closures.
///
/// The host app is responsible for presenting its own export/share UI from
/// the ``onExport`` callback and its own settings UI from ``onShowSettings``.
public struct ScanPreviewView: View {
    @EnvironmentObject private var scanStore: ScanStore
    @Environment(\.dismiss) private var dismiss

    public let scan: Scan
    private let onExport: (Scan, SCMesh?) -> Void
    private let onShowSettings: (() -> Void)?

    @StateObject private var meshingService = MeshingService()

    @State private var sceneViewRef: SCNView?

    public init(
        scan: Scan,
        onExport: @escaping (Scan, SCMesh?) -> Void,
        onShowSettings: (() -> Void)? = nil
    ) {
        self.scan = scan
        self.onExport = onExport
        self.onShowSettings = onShowSettings
    }

    public var body: some View {
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

                VStack(alignment: .trailing, spacing: 16) {
                    Button {
                        onExport(scan, meshingService.mesh)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.body)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.systemBackground).opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                    .accessibilityLabel("Share")

                    if let onShowSettings {
                        Button {
                            onShowSettings()
                        } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(.blue)
                                .frame(width: 27, height: 27)
                        }
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
                    VStack(spacing: 24) {
                        if !meshingService.isRunning {
                            Button {
                                if meshingService.mesh != nil {
                                    onExport(scan, meshingService.mesh)
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

                            Button("Done") {
                                if scan.plyPath == nil {
                                    scanStore.add(scan)
                                }
                                dismiss()
                            }
                            .padding(.bottom, 4)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 40)
            }
        }
    }
}

#endif
