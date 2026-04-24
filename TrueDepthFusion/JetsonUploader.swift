//
//  JetsonUploader.swift
//  TrueDepthFusion
//

import Foundation
import UIKit

class JetsonUploader {

    private static let ipKey = "jetson_ip"
    private static let portKey = "jetson_port"

    static var jetsonIP: String {
        get { UserDefaults.standard.string(forKey: ipKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: ipKey) }
    }

    static var jetsonPort: String {
        get { UserDefaults.standard.string(forKey: portKey) ?? "8080" }
        set { UserDefaults.standard.set(newValue, forKey: portKey) }
    }

    // MARK: - Upload

    static func upload(plyFileURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let ip = jetsonIP.trimmingCharacters(in: .whitespaces)
        let port = jetsonPort.trimmingCharacters(in: .whitespaces)

        guard !ip.isEmpty, let serverURL = URL(string: "http://\(ip):\(port)/upload") else {
            completion(.failure(makeError("Invalid Jetson IP address. Please configure it via the settings button.")))
            return
        }

        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let filename = plyFileURL.lastPathComponent

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")

        do {
            body.append(try Data(contentsOf: plyFileURL))
        } catch {
            completion(.failure(error))
            return
        }

        body.append("\r\n--\(boundary)--\r\n")

        URLSession.shared.uploadTask(with: request, from: body) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    completion(.failure(makeError("Server returned HTTP \(http.statusCode)")))
                } else {
                    completion(.success(()))
                }
            }
        }.resume()
    }

    // MARK: - Settings UI

    static func showSettings(from viewController: UIViewController) {
        let alert = UIAlertController(title: "Jetson Settings", message: "Enter the IP address and port of the Jetson server.", preferredStyle: .alert)

        alert.addTextField { field in
            field.placeholder = "IP address (e.g. 192.168.1.100)"
            field.text = JetsonUploader.jetsonIP
            field.keyboardType = .decimalPad
            field.clearButtonMode = .whileEditing
        }

        alert.addTextField { field in
            field.placeholder = "Port (default: 8080)"
            field.text = JetsonUploader.jetsonPort
            field.keyboardType = .numberPad
            field.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            JetsonUploader.jetsonIP = alert.textFields?[0].text ?? ""
            JetsonUploader.jetsonPort = alert.textFields?[1].text?.isEmpty == false ? alert.textFields?[1].text ?? "8080" : "8080"
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        viewController.present(alert, animated: true)
    }

    // MARK: - Result UI

    static func showResult(_ result: Result<Void, Error>, from viewController: UIViewController) {
        let alert: UIAlertController
        switch result {
        case .success:
            alert = UIAlertController(title: "Sent", message: "PLY file uploaded to Jetson successfully.", preferredStyle: .alert)
        case .failure(let error):
            alert = UIAlertController(title: "Upload Failed", message: error.localizedDescription, preferredStyle: .alert)
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }

    // MARK: - Private

    private static func makeError(_ message: String) -> Error {
        NSError(domain: "JetsonUploader", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
