//
//  Route.swift

import Foundation

/// Type-safe push navigation destinations.
enum Route: Hashable {
    case scansList
}

/// Type-safe full-screen cover destinations.
enum FullScreenDestination: Identifiable {
    case scanning
    case bplyScanning

    var id: String {
        switch self {
        case .scanning: return "scanning"
        case .bplyScanning: return "bplyScanning"
        }
    }
}
