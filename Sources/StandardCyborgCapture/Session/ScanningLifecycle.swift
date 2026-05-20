//
//  ScanningLifecycle.swift

#if os(iOS)

import Combine
import Foundation
import StandardCyborgCaptureObjC

public enum TerminationReason: Sendable {
    case canceled
    case finished
}

@MainActor
public final class ScanningLifecycle: ObservableObject {

    @Published public private(set) var state: ScanningState = .idle

    public let configuration: ScanningConfiguration
    public weak var feedbackProvider: (any ScanFeedbackProvider)?

    private var scanningTimer: Timer?
    nonisolated(unsafe) private var thermalObserver: (any NSObjectProtocol)?

    public init(configuration: ScanningConfiguration = .default) {
        self.configuration = configuration
        self.scanDurationSeconds = configuration.defaultScanDurationSeconds
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.object as? ProcessInfo,
                  info.thermalState == .critical else { return }
            Task { @MainActor [weak self] in
                guard let self, self.state.isScanning else { return }
                self.stopScanning(reason: .finished)
                self.feedbackProvider?.scanningFailed(.thermalShutdown)
            }
        }
    }

    deinit {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    // MARK: - State Transitions

    public func requestStartCountdown() {
        guard state.isIdle else { return }
        transition(to: .countdown(remaining: configuration.countdownSeconds))
        iterateCountdown()
    }

    public func cancelCountdown() {
        guard state.countdownRemaining != nil else { return }
        feedbackProvider?.scanningCanceled()
        transition(to: .idle)
    }

    public func beginScanning() {
        transition(to: .scanning(elapsed: 0))
        feedbackProvider?.scanningBegan()

        scanningTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard case .scanning(let elapsed) = self.state else { return }
                let next = elapsed + 1
                self.updateState(.scanning(elapsed: next))
                self.feedbackProvider?.scanningProgress(elapsed: next, frameCount: 0)
                if !self.configuration.tapToStartStop && next >= self.scanDurationSeconds {
                    self.stopScanning(reason: .finished)
                }
            }
        }
        RunLoop.current.add(scanningTimer!, forMode: .default)
    }

    public func stopScanning(reason: TerminationReason) {
        guard state.isScanning else { return }
        scanningTimer?.invalidate()
        scanningTimer = nil

        switch reason {
        case .canceled:
            feedbackProvider?.scanningCanceled()
            transition(to: .idle)
        case .finished:
            transition(to: .finalizing)
            feedbackProvider?.scanningFinished()
        }
    }

    public func markCompleted(_ scan: Scan) {
        transition(to: .completed(ScanRef(scan)))
    }

    public func markFailed(_ error: ScanningError) {
        scanningTimer?.invalidate()
        scanningTimer = nil
        feedbackProvider?.scanningFailed(error)
        transition(to: .failed(error))
    }

    public func reset() {
        scanningTimer?.invalidate()
        scanningTimer = nil
        updateState(.idle)
    }

    // MARK: - Scan Duration

    @Published public var scanDurationSeconds: Int = 5

    // MARK: - Private

    private func transition(to newState: ScanningState) {
        let oldState = state
        guard oldState.canTransition(to: newState) else { return }
        state = newState
        feedbackProvider?.stateChanged(from: oldState, to: newState)
    }

    private func updateState(_ newState: ScanningState) {
        let oldState = state
        state = newState
        feedbackProvider?.stateChanged(from: oldState, to: newState)
    }

    private func iterateCountdown() {
        guard let remaining = state.countdownRemaining else { return }
        if remaining == 0 {
            beginScanning()
            return
        }
        feedbackProvider?.countdownCountedDown()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let current = self.state.countdownRemaining, current > 0 else { return }
            self.updateState(.countdown(remaining: current - 1))
            self.iterateCountdown()
        }
    }
}

#endif
