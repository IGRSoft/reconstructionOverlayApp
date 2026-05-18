//
//  ScansListView.swift

import SwiftUI
import TrueDepthFusionObjC
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
                                exportContext = ExportContext(scan: scan, mode: .export)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)

                            Button {
                                exportContext = ExportContext(scan: scan, mode: .jetson)
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
            ScanPreviewView(scan: selection.scan)
                .environmentObject(scanStore)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showJetsonSettings) {
            JetsonSettingsView()
        }
        .sheet(item: $exportContext) { ctx in
            ExportNameView(context: ctx, scanStore: scanStore)
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

// MARK: - ScanSelection

struct ScanSelection: Identifiable {
    let id = UUID()
    let scan: Scan
}

// MARK: - ExportContext

struct ExportContext: Identifiable {
    enum Mode { case export, jetson }
    let id = UUID()
    let scan: Scan
    let mode: Mode
}

// MARK: - ExportNameView (name-prompt sheet)

private struct ExportNameView: View {
    let context: ExportContext
    let scanStore: ScanStore

    @State private var name: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

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
                            dismiss()
                        }
                    }
                    .disabled(isWorking)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func perform() async {
        let namePrefix = Self.sanitize(name)
        switch context.mode {
        case .export:
            await exportPLY(scan: context.scan, namePrefix: namePrefix)
        case .jetson:
            await sendToJetson(scan: context.scan, namePrefix: namePrefix)
        }
    }

    private func exportPLY(scan: Scan, namePrefix: String) async {
        guard scan.plyPath != nil else { return }
        let baseURL = scan.writeCompressedPLY()
        let renamedURL = baseURL.deletingLastPathComponent()
            .appendingPathComponent(Self.outputFilename(name: namePrefix))
        try? FileManager.default.removeItem(at: renamedURL)
        try? FileManager.default.copyItem(at: baseURL, to: renamedURL)
        await MainActor.run {
            let av = UIActivityViewController(activityItems: [renamedURL], applicationActivities: nil)
            UIApplication.shared.topViewController()?.present(av, animated: true)
        }
    }

    private func sendToJetson(scan: Scan, namePrefix: String) async {
        guard let plyPath = scan.plyPath else { return }
        let renamedPath = NSTemporaryDirectory() + Self.outputFilename(name: namePrefix)
        try? FileManager.default.removeItem(atPath: renamedPath)
        try? FileManager.default.copyItem(atPath: plyPath, toPath: renamedPath)
        let url = URL(fileURLWithPath: renamedPath)
        JetsonUploader.upload(plyFileURL: url) { result in
            Task { @MainActor in
                if let vc = UIApplication.shared.topViewController() {
                    JetsonUploader.showResult(result, from: vc)
                }
            }
        }
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

