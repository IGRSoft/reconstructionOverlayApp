//
//  PointCloudRenderer.swift
//  Swift port of SCPointCloudRenderer.m

import AVFoundation
import Metal
import MetalKit
import StandardCyborgFusion
import simd

// SharedUniforms must match the struct definition in SCPointCloudRenderer.metal
private struct SharedUniforms {
    var viewNormalMatrix: simd_float3x3
    var viewMatrix: simd_float4x4
    var viewProjectionMatrix: simd_float4x4
    var pointSize: Float
}

final class SCPointCloudRenderer {

    private let _device: MTLDevice
    private let _pipelineState: MTLRenderPipelineState
    private let _depthStencilState: MTLDepthStencilState
    private let _sharedUniformsBuffer: MTLBuffer
    private let _matcapTexture: MTLTexture
    private var _depthTexture: MTLTexture?

    init(device: MTLDevice, library: MTLLibrary) {
        _device = device

        let textureLoader = MTKTextureLoader(device: device)
        _matcapTexture = (try? textureLoader.newTexture(
            name: "matcap",
            scaleFactor: 1.0,
            bundle: nil,
            options: [.SRGB: false as NSNumber]
        )) ?? device.makeTexture(descriptor: MTLTextureDescriptor())!

        let vertexFunction = library.makeFunction(name: "RenderSCPointCloudVertex")!
        let fragmentFunction = library.makeFunction(name: "RenderSCPointCloudFragment")!

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = SCPointCloudRenderer._pointCloudVertexDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.label = "SCPointCloudRenderer._pipelineState"

        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.label = "SCPointCloudRenderer._depthStencilState"
        _depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!

        _pipelineState = (try? device.makeRenderPipelineState(descriptor: pipelineDescriptor)) ?? {
            fatalError("Unable to create SCPointCloudRenderer pipeline state")
        }()

        _sharedUniformsBuffer = device.makeBuffer(
            length: MemoryLayout<SharedUniforms>.stride,
            options: .cpuCacheModeWriteCombined
        )!
        _sharedUniformsBuffer.label = "SCPointCloudRenderer._sharedUniformsBuffer"
    }

    // NS_SWIFT_NAME preserved: encodeCommands(onto:pointCloud:depthCameraCalibrationData:viewMatrix:outputTexture:depthFrameSize:flipsInputHorizontally:)
    func encodeCommands(onto commandBuffer: MTLCommandBuffer,
                        pointCloud: SCPointCloud,
                        depthCameraCalibrationData: AVCameraCalibrationData,
                        viewMatrix: matrix_float4x4,
                        outputTexture: MTLTexture,
                        depthFrameSize: CGSize,
                        flipsInputHorizontally: Bool)
    {
        guard pointCloud.pointCount > 0 else { return }

        if _depthTexture == nil {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float,
                width: outputTexture.width,
                height: outputTexture.height,
                mipmapped: false
            )
            descriptor.usage = .renderTarget
            descriptor.storageMode = .private
            _depthTexture = _device.makeTexture(descriptor: descriptor)
            _depthTexture?.label = "SCPointCloudRenderer._depthTexture"
        }

        let pointsBuffer = pointCloud.buildPointsMTLBuffer(with: _device)
        pointsBuffer.label = "SCPointCloudRenderer.pointsBuffer"

        _updateSharedUniformsBuffer(
            intrinsicMatrix: depthCameraCalibrationData.intrinsicMatrix,
            intrinsicMatrixReferenceDimensions: depthCameraCalibrationData.intrinsicMatrixReferenceDimensions,
            viewMatrix: viewMatrix,
            resultWidth: outputTexture.width,
            resultHeight: outputTexture.height,
            depthFrameSize: depthFrameSize,
            flipsInputHorizontally: flipsInputHorizontally
        )

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = outputTexture
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].loadAction = .load
        passDescriptor.depthAttachment.texture = _depthTexture
        passDescriptor.depthAttachment.loadAction = .clear
        passDescriptor.depthAttachment.storeAction = .dontCare
        passDescriptor.depthAttachment.clearDepth = 1.0

        guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        commandEncoder.label = "SCPointCloudRenderer.commandEncoder"

        commandEncoder.setRenderPipelineState(_pipelineState)
        commandEncoder.setViewport(MTLViewport(
            originX: 0, originY: 0,
            width: Double(outputTexture.width), height: Double(outputTexture.height),
            znear: -1, zfar: 1
        ))
        commandEncoder.setDepthStencilState(_depthStencilState)
        commandEncoder.setFrontFacing(.counterClockwise)
        commandEncoder.setCullMode(.back)
        commandEncoder.setVertexBuffer(pointsBuffer, offset: 0, index: 0)
        commandEncoder.setVertexBuffer(_sharedUniformsBuffer, offset: 0, index: 1)
        commandEncoder.setFragmentTexture(_matcapTexture, index: 0)
        commandEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCloud.pointCount)

        commandEncoder.endEncoding()
    }

    // MARK: - Private

    private static func _pointCloudVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.layouts[0].stride = SCPointCloud.pointStride()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = SCPointCloud.positionOffset()
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = SCPointCloud.normalOffset()
        descriptor.attributes[2].format = .float3
        descriptor.attributes[2].offset = SCPointCloud.colorOffset()
        descriptor.attributes[3].format = .float
        descriptor.attributes[3].offset = SCPointCloud.weightOffset()
        return descriptor
    }

    private func _updateSharedUniformsBuffer(intrinsicMatrix: matrix_float3x3,
                                              intrinsicMatrixReferenceDimensions: CGSize,
                                              viewMatrix: matrix_float4x4,
                                              resultWidth: Int,
                                              resultHeight: Int,
                                              depthFrameSize: CGSize,
                                              flipsInputHorizontally: Bool)
    {
        let fx = intrinsicMatrix.columns.0.x
        let fy = intrinsicMatrix.columns.1.y
        let sourceWidth = Float(intrinsicMatrixReferenceDimensions.width)
        let sourceHeight = Float(intrinsicMatrixReferenceDimensions.height)

        let near: Float = 0.001
        let far: Float = 10.0

        let resultAspectRatio = Float(resultWidth) / Float(resultHeight)
        // Source aspect ratio inverted because the incoming frame is sideways
        let sourceAspectRatio = sourceHeight / sourceWidth

        let nominalPointSize: Float = 8.0
        let nominalFrameWidth: Float = 640.0
        let nominalResultHeight: Float = 1556.0
        let pointSize = nominalPointSize * (nominalFrameWidth / Float(depthFrameSize.width)) * (Float(resultHeight) / nominalResultHeight)

        var imageScale = simd_float2(0, 0)
        let referenceSize: Float
        if sourceAspectRatio > resultAspectRatio {
            imageScale[0] = 1.0 / resultAspectRatio
            imageScale[1] = 1.0
            referenceSize = sourceWidth
        } else {
            imageScale[0] = 1.0
            imageScale[1] = resultAspectRatio
            referenceSize = sourceHeight
        }

        let projection = simd_float4x4(columns: (
            simd_float4(2.0 * fx / referenceSize * imageScale[0], 0, 0, 0),
            simd_float4(0, 2.0 * fy / referenceSize * imageScale[1], 0, 0),
            simd_float4(0, 0, (far + near) / (near - far), -1),
            simd_float4(0, 0, 2.0 * far * near / (near - far), 0)
        ))

        let viewInverse = matrix_invert(viewMatrix)

        let orientationTransform: simd_float4x4
        if flipsInputHorizontally {
            orientationTransform = simd_float4x4(columns: (
                simd_float4(-1.0, 0.0,  0.0, 0.0),
                simd_float4( 0.0, 1.0,  0.0, 0.0),
                simd_float4( 0.0, 0.0, -1.0, 0.0),
                simd_float4( 0.0, 0.0,  0.0, 1.0)
            ))
        } else {
            orientationTransform = simd_float4x4(columns: (
                simd_float4(1.0, 0.0,  0.0, 0.0),
                simd_float4(0.0, 1.0,  0.0, 0.0),
                simd_float4(0.0, 0.0, -1.0, 0.0),
                simd_float4(0.0, 0.0,  0.0, 1.0)
            ))
        }

        let view = matrix_multiply(orientationTransform, viewInverse)

        let truncatedView = simd_float3x3(columns: (
            simd_float3(view.columns.0.x, view.columns.0.y, view.columns.0.z),
            simd_float3(view.columns.1.x, view.columns.1.y, view.columns.1.z),
            simd_float3(view.columns.2.x, view.columns.2.y, view.columns.2.z)
        ))
        let viewNormalMatrix = matrix_transpose(matrix_invert(truncatedView))
        let viewProjectionMatrix = matrix_multiply(projection, matrix_multiply(orientationTransform, viewInverse))

        var uniforms = SharedUniforms(
            viewNormalMatrix: viewNormalMatrix,
            viewMatrix: view,
            viewProjectionMatrix: viewProjectionMatrix,
            pointSize: pointSize
        )

        memcpy(_sharedUniformsBuffer.contents(), &uniforms, MemoryLayout<SharedUniforms>.stride)
    }
}
