//
//  ScanningError.swift

#if os(iOS)

import Foundation

public enum ScanningError: Error, Sendable, Equatable {
    case cameraNotAuthorized
    case cameraConfigurationFailed
    case reconstructionFailed(frameCount: Int)
    case thermalShutdown
}

#endif
