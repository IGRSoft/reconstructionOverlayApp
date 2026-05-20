//
//  ScanningState.swift

#if os(iOS)

import Foundation
import StandardCyborgCaptureObjC

public enum ScanningState: Sendable {
    case idle
    case countdown(remaining: Int)
    case scanning(elapsed: Int)
    case finalizing
    case completed(ScanRef)
    case failed(ScanningError)

    public var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    public var countdownRemaining: Int? {
        if case .countdown(let remaining) = self { return remaining }
        return nil
    }

    public var elapsed: Int? {
        if case .scanning(let elapsed) = self { return elapsed }
        return nil
    }

    func canTransition(to target: ScanningState) -> Bool {
        switch (self, target) {
        case (.idle, .countdown): return true
        case (.countdown, .idle): return true
        case (.countdown, .scanning): return true
        case (.scanning, .finalizing): return true
        case (.scanning, .failed): return true
        case (.scanning, .idle): return true
        case (.finalizing, .completed): return true
        case (.finalizing, .failed): return true
        case (.completed, .idle): return true
        case (.failed, .idle): return true
        default: return false
        }
    }
}

extension ScanningState: Equatable {
    public static func == (lhs: ScanningState, rhs: ScanningState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.countdown(let a), .countdown(let b)): return a == b
        case (.scanning(let a), .scanning(let b)): return a == b
        case (.finalizing, .finalizing): return true
        case (.completed(let a), .completed(let b)): return a.id == b.id
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

/// Sendable wrapper for Scan identity in state enum.
/// Scan is an ObjC class that cannot conform to Sendable directly.
public struct ScanRef: Sendable {
    public let id: ObjectIdentifier
    public nonisolated(unsafe) let scan: Scan

    public init(_ scan: Scan) {
        self.id = ObjectIdentifier(scan)
        self.scan = scan
    }
}

#endif
