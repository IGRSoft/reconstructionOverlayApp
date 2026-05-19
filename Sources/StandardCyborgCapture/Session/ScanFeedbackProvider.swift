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
}

#endif
