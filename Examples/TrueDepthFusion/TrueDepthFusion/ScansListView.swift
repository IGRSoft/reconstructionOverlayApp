//
//  ScansListView.swift

import StandardCyborgCapture
import StandardCyborgCaptureObjC
import StandardCyborgFusion
import SwiftUI
import UIKit

struct ScansListView: View {
    @EnvironmentObject private var scanStore: ScanStore

    @State private var selectedScan: ScanSelection?
    @State private var showJetsonSettings = false
    @State private var exportContext: ExportContext?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if scanStore.scans.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView("No Scans", systemImage: "cube.transparent", description: nil)
                } else {
                    Text("No Scans")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List {
                    ForEach(scanStore.scans, id: \.self) { scan in
                        ScanRow(
                            scan: scan,
                            dateString: ScansListView.dateFormatter.string(from: scan.dateCreated),
                            timeString: ScansListView.timeFormatter.string(from: scan.dateCreated)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedScan = ScanSelection(scan: scan) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                scanStore.remove(scan)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                exportContext = ExportContext(scan: scan, mesh: nil, target: .share)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)

                            Button {
                                exportContext = ExportContext(scan: scan, mesh: nil, target: .jetson)
                            } label: {
                                Label("Send to Robot", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .tint(.indigo)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Scans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showJetsonSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(item: $selectedScan) { selection in
            ScanPreviewView(
                scan: selection.scan,
                onExport: { scan, mesh in
                    exportContext = ExportContext(scan: scan, mesh: mesh, target: .share)
                },
                onShowSettings: {
                    showJetsonSettings = true
                }
            )
            .environmentObject(scanStore)
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showJetsonSettings) {
            JetsonSettingsView()
        }
        .sheet(item: $exportContext) { ctx in
            ExportSheet(scan: ctx.scan, mesh: ctx.mesh, target: ctx.target)
                .environmentObject(scanStore)
        }
    }
}

// MARK: - ScanRow

private struct ScanRow: View {
    let scan: Scan
    let dateString: String
    let timeString: String

    var body: some View {
        HStack(spacing: 12) {
            if let img = scan.thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(dateString)
                    .font(.body)
                Text(timeString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ExportContext

struct ExportContext: Identifiable {
    let id = UUID()
    let scan: Scan
    let mesh: SCMesh?
    let target: ExportTarget
}
