//
//  ScanFeedbackProvider.swift

#if os(iOS)

import Foundation

@MainActor
public protocol ScanFeedbackProvider: AnyObject {
    func countdownCountedDown()
    func scanningBegan()
    func scanningFinished()
    func scanningCanceled()

    func scanningProgress(elapsed: Int, frameCount: Int)
    func distanceGuidanceChanged(_ message: String?)
    func scanningFailed(_ error: ScanningError)
    func stateChanged(from: ScanningState, to: ScanningState)
}

extension ScanFeedbackProvider {
    public func scanningProgress(elapsed: Int, frameCount: Int) {}
    public func distanceGuidanceChanged(_ message: String?) {}
    public func scanningFailed(_ error: ScanningError) {}
    public func stateChanged(from: ScanningState, to: ScanningState) {}
}

#endif
