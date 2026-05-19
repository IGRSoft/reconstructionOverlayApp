//
//  ScanPreviewControls.swift

import StandardCyborgCapture
import StandardCyborgCaptureObjC
import StandardCyborgFusion
import SwiftUI

struct ScanPreviewControls: View {
    @EnvironmentObject private var scanStore: ScanStore
    @Environment(\.dismiss) private var dismiss

    let scan: Scan
    @ObservedObject var meshingService: MeshingService
    var showSettings: Bool = true

    @State private var exportContext: ExportContext?
    @State private var showJetsonSettings = false

    var body: some View {
        Group {
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
                        exportContext = ExportContext(scan: scan, mesh: meshingService.mesh, target: .share)
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

                    if showSettings {
                        Button {
                            showJetsonSettings = true
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
                                    exportContext = ExportContext(scan: scan, mesh: meshingService.mesh, target: .share)
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
        .sheet(item: $exportContext) { ctx in
            ExportSheet(scan: ctx.scan, mesh: ctx.mesh, target: ctx.target)
                .environmentObject(scanStore)
        }
        .sheet(isPresented: $showJetsonSettings) {
            JetsonSettingsView()
        }
    }
}
