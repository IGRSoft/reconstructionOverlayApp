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
/// Construct once per Metal device. The renderer caches its pipeline state and
/// is safe to drive from a single serial camera queue.
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

    public func draw(colorBuffer: CVPixelBuffer,
                     depthBuffer: CVPixelBuffer?,
                     pointCloud: SCPointCloud?,
                     depthCameraCalibrationData: AVCameraCalibrationData,
                     viewMatrix: matrix_float4x4,
                     into metalLayer: CAMetalLayer,
                     flipsInputHorizontally: Bool)
    {
        _inflightSemaphore.wait()

        autoreleasepool {
            let commandBuffer = _commandQueue.makeCommandBuffer()!
            commandBuffer.label = "ScanningViewRenderer.commandBuffer"

            guard let drawable = metalLayer.nextDrawable() else {
                _inflightSemaphore.signal()
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

            commandBuffer.addCompletedHandler { [weak self] _ in
                self?._inflightSemaphore.signal()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

#endif
