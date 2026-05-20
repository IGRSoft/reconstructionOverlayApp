//
//  LoggingCameraManager.swift
//
//  Example showing how to implement `CameraManagerProtocol` to plug a custom
//  camera pipeline into `ScanningSession`. This implementation is a decorator:
//  it wraps a real `CameraManager`, forwards every call, and logs lifecycle
//  events plus periodic frame counters via `os.Logger`.

#if os(iOS)

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import os
import StandardCyborgCapture

/// Drop-in `CameraManagerProtocol` replacement that wraps a real `CameraManager`
/// and logs every protocol call plus every 30th frame.
final class LoggingCameraManager: NSObject, CameraManagerProtocol, CameraManagerDelegate, @unchecked Sendable {

    weak var delegate: CameraManagerDelegate?

    var isFocusLocked: Bool {
        get { inner.isFocusLocked }
        set {
            log.debug("isFocusLocked = \(newValue, privacy: .public)")
            inner.isFocusLocked = newValue
        }
    }

    var paused: Bool {
        get { inner.paused }
        set {
            log.debug("paused = \(newValue, privacy: .public)")
            inner.paused = newValue
        }
    }

    override init() {
        super.init()
        inner.delegate = self
    }

    func configureCaptureSession(maxColorResolution: Int,
                                 maxDepthResolution: Int,
                                 maxFramerate: Int) {
        log.info("configureCaptureSession color=\(maxColorResolution, privacy: .public) depth=\(maxDepthResolution, privacy: .public) fps=\(maxFramerate, privacy: .public)")
        inner.configureCaptureSession(maxColorResolution: maxColorResolution,
                                      maxDepthResolution: maxDepthResolution,
                                      maxFramerate: maxFramerate)
    }

    func startSession(_ completion: (@Sendable (SessionSetupResult) -> Void)?) {
        log.info("startSession requested")
        inner.startSession { [log] result in
            log.info("startSession result=\(String(describing: result), privacy: .public)")
            completion?(result)
        }
    }

    func stopSession() {
        log.info("stopSession; total frames=\(self.frameCount, privacy: .public)")
        inner.stopSession()
    }

    func focusOnTap(at location: CGPoint) {
        log.debug("focusOnTap at (\(location.x, privacy: .public), \(location.y, privacy: .public))")
        inner.focusOnTap(at: location)
    }

    // MARK: - CameraManagerDelegate (frame interception)

    func cameraDidOutput(colorBuffer: CVPixelBuffer,
                         colorTime: CMTime,
                         depthBuffer: CVPixelBuffer,
                         depthTime: CMTime,
                         depthCalibrationData: AVCameraCalibrationData) {
        frameCount &+= 1
        if frameCount % 30 == 0 {
            log.debug("frame #\(self.frameCount, privacy: .public)")
        }
        delegate?.cameraDidOutput(colorBuffer: colorBuffer,
                                  colorTime: colorTime,
                                  depthBuffer: depthBuffer,
                                  depthTime: depthTime,
                                  depthCalibrationData: depthCalibrationData)
    }

    // MARK: - Private

    private let inner = CameraManager()
    private let log = Logger(subsystem: "com.standardcyborg.TrueDepthFusion", category: "Camera")
    private var frameCount = 0
}

#endif
