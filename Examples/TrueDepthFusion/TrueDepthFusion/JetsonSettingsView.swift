//
//  JetsonSettingsView.swift

import SwiftUI

struct JetsonSettingsView: View {
    @State private var ip: String = JetsonUploader.jetsonIP
    @State private var port: String = JetsonUploader.jetsonPort
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Jetson Server")) {
                    LabeledContent("IP Address") {
                        TextField("192.168.1.100", text: $ip)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    LabeledContent("Port") {
                        TextField("8080", text: $port)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("Jetson Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        JetsonUploader.jetsonIP = ip
                        JetsonUploader.jetsonPort = port.isEmpty ? "8080" : port
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
