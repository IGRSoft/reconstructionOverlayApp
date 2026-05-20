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

    var id: String {
        switch self {
        case .scanning: return "scanning"
        }
    }
}
