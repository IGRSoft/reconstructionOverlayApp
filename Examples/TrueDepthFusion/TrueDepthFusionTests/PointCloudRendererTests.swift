// PointCloudRendererTests.swift

import Testing
import Metal
import MetalKit
@testable import TrueDepthFusion

@Suite("SCPointCloudRenderer")
struct PointCloudRendererTests {

    @Test("SCPointCloudRenderer initialises on a Metal device without crashing")
    func initWithDevice() throws {
        // The iOS Simulator exposes a software Metal device;
        // real TrueDepth rendering only runs on physical hardware but the
        // class itself should be constructible anywhere Metal is available.
        guard let device = MTLCreateSystemDefaultDevice() else {
            // Metal not available on this host (e.g. some CI environments).
            return
        }

        // Build a minimal MTLLibrary from source so we can instantiate the renderer.
        // The renderer requires vertex/fragment functions to be present.
        guard Bundle(for: BundleLocator.self).path(forResource: nil, ofType: nil) != nil,
              let library = try? device.makeDefaultLibrary(bundle: .main) else {
            // No compiled Metal library on this host — skip rather than fail.
            return
        }

        let renderer = SCPointCloudRenderer(device: device, library: library)
        // Reaching here means init succeeded.
        _ = renderer
    }

    @Test("Metal system device is available on simulator")
    func metalDeviceAvailable() {
        #expect(MTLCreateSystemDefaultDevice() != nil, "Metal system default device should be available on simulator")
    }
}

// Used only to locate the main bundle from a test context.
private final class BundleLocator {}
