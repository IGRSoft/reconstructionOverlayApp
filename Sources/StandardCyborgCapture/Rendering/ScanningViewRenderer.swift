//
//  ScanningViewRenderer.swift

#if os(iOS)

import AVFoundation
import Foundation
import Metal
import StandardCyborgFusion

/// Composes `DepthColoringFilter` (live camera + depth) and `SCPointCloudRenderer`
/// (accumulated point cloud) into a single Metal layer presentation pass.
///
/// Construct once per Metal device. The renderer caches its pipeline state,
/// point-cloud MTL buffer, depth/uniform state, and Metal texture cache with NO
/// internal locking. `draw(...)` MUST be invoked from exactly one serial queue —
/// `ScanningSession._renderQueue` — for the lifetime of the session. Both the
/// decoupled (async, drop-if-busy) and the fallback (synchronous) paths route
/// through that single queue; `draw(...)` is never called on the camera
/// data-output queue. Violating this single-queue contract races the unlocked
/// caches in `DepthColoringFilter` and `SCPointCloudRenderer`.
public final class ScanningViewRenderer: @unchecked Sendable {

    private let _device: MTLDevice
    private let _library: MTLLibrary
    private let _commandQueue: MTLCommandQueue
    private let _depthColoringFilter: DepthColoringFilter
    private let _pointCloudRenderer: SCPointCloudRenderer
    private let _inflightSemaphore = DispatchSemaphore(value: 2)

    /// - Throws: `MetalLibraryError.libraryNotFound` if `Bundle.module` does not
    ///   contain the package's compiled Metal library.
    public init(device: MTLDevice, commandQueue: MTLCommandQueue) throws {
        _device = device
        _commandQueue = commandQueue
        _library = try device.makeStandardCyborgCaptureLibrary()

        _depthColoringFilter = DepthColoringFilter(device: _device, library: _library)
        _pointCloudRenderer = SCPointCloudRenderer(device: _device, library: _library)
    }

    /// - Parameter onRenderComplete: Called exactly once per `draw(...)` invocation,
    ///   on every exit path. On the success path it fires from inside the
    ///   command-buffer completion handler (co-located with the inflight-semaphore
    ///   signal), i.e. at the true end of GPU work; on every early-return path it
    ///   fires before returning. The caller uses it to release the drop-if-busy
    ///   render slot. `@Sendable` because the completion handler runs off-thread.
    public func draw(colorBuffer: CVPixelBuffer,
                     depthBuffer: CVPixelBuffer?,
                     pointCloud: SCPointCloud?,
                     depthCameraCalibrationData: AVCameraCalibrationData,
                     viewMatrix: matrix_float4x4,
                     into metalLayer: CAMetalLayer,
                     flipsInputHorizontally: Bool,
                     onRenderComplete: @escaping @Sendable () -> Void = {})
    {
        _inflightSemaphore.wait()

        autoreleasepool {
            let commandBuffer = _commandQueue.makeCommandBuffer()!
            commandBuffer.label = "ScanningViewRenderer.commandBuffer"

            guard let drawable = metalLayer.nextDrawable() else {
                _inflightSemaphore.signal()
                onRenderComplete()
                return
            }
            let outputTexture = drawable.texture

            let hasPointCloud = depthBuffer != nil && pointCloud != nil && (pointCloud?.pointCount ?? 0) > 0

            _depthColoringFilter.encodeCommands(onto: commandBuffer,
                                                colorBuffer: colorBuffer,
                                                depthBuffer: nil,
                                                outputTexture: outputTexture,
                                                dimPreview: hasPointCloud)

            if let depthBuffer = depthBuffer,
               let pointCloud = pointCloud,
               pointCloud.pointCount > 0
            {
                let depthFrameSize = CGSize(width: CVPixelBufferGetWidth(depthBuffer),
                                            height: CVPixelBufferGetHeight(depthBuffer))

                _pointCloudRenderer.encodeCommands(onto: commandBuffer,
                                                   pointCloud: pointCloud,
                                                   depthCameraCalibrationData: depthCameraCalibrationData,
                                                   viewMatrix: viewMatrix,
                                                   outputTexture: outputTexture,
                                                   depthFrameSize: depthFrameSize,
                                                   flipsInputHorizontally: flipsInputHorizontally)
            }

            // Capture the semaphore strongly so it outlives the renderer if
            // the view is torn down between commit and GPU completion.
            // libdispatch traps if a semaphore is deallocated with
            // value < original (i.e. an outstanding wait at dealloc time).
            let semaphore = _inflightSemaphore
            commandBuffer.addCompletedHandler { _ in
                semaphore.signal()
                onRenderComplete()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

#endif
