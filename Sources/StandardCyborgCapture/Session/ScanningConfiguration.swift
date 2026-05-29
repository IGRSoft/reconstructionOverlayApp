//
//  ScanningConfiguration.swift

#if os(iOS)

public struct ScanningConfiguration: Sendable {
    public var tapToStartStop: Bool
    public var useFullResolutionDepthFrames: Bool
    public var stopScanOnReconstructionFailure: Bool
    public var defaultScanDurationSeconds: Int
    public var countdownSeconds: Int

    /// Maximum color (RGB) capture width in pixels.
    ///
    /// Defaults to `1280` (720p). This is an intentional performance choice: the 720p
    /// preset keeps the per-frame color buffer small, reducing GPU upload and
    /// reconstruction cost during live scanning. Earlier builds defaulted to `1920`
    /// (1080p). Consumers that specifically need 1080p color must opt back in
    /// explicitly by passing `maxColorResolution: 1920`.
    public var maxColorResolution: Int
    public var maxFramerate: Int
    public var lowResDepthResolution: Int
    public var highResDepthResolution: Int

    public var nearDistanceMeters: Float
    public var farDistanceMeters: Float

    public var failedScanMinFrameCount: Int
    public var failedScanDismissDelaySeconds: Double

    /// 0 = keep the reconstruction engine's built-in default.
    public var maxICPIterations: Int32
    /// 0 = keep the reconstruction engine's built-in default.
    public var icpTolerance: Float

    public var bplyExportEnabled: Bool

    /// When true (default), the live-preview draw runs on a dedicated serial
    /// render queue with latest-frame-wins / drop-if-busy coalescing, decoupling
    /// the GPU-blocking draw from camera intake. When false, the draw runs
    /// synchronously (blocking the camera queue, original behavior) for a
    /// one-line A/B comparison on device.
    public var decoupledRenderingEnabled: Bool

    public init(
        tapToStartStop: Bool = false,
        useFullResolutionDepthFrames: Bool = false,
        stopScanOnReconstructionFailure: Bool = true,
        defaultScanDurationSeconds: Int = 5,
        countdownSeconds: Int = 3,
        // Default 1280 (720p) is an intentional perf choice; pass 1920 to opt back in to 1080p.
        maxColorResolution: Int = 1280,
        maxFramerate: Int = 30,
        lowResDepthResolution: Int = 320,
        highResDepthResolution: Int = 640,
        nearDistanceMeters: Float = 0.25,
        farDistanceMeters: Float = 0.60,
        failedScanMinFrameCount: Int = 50,
        failedScanDismissDelaySeconds: Double = 3.8,
        maxICPIterations: Int32 = 0,
        icpTolerance: Float = 0,
        bplyExportEnabled: Bool = false,
        decoupledRenderingEnabled: Bool = true
    ) {
        self.tapToStartStop = tapToStartStop
        self.useFullResolutionDepthFrames = useFullResolutionDepthFrames
        self.stopScanOnReconstructionFailure = stopScanOnReconstructionFailure
        self.defaultScanDurationSeconds = defaultScanDurationSeconds
        self.countdownSeconds = countdownSeconds
        self.maxColorResolution = maxColorResolution
        self.maxFramerate = maxFramerate
        self.lowResDepthResolution = lowResDepthResolution
        self.highResDepthResolution = highResDepthResolution
        self.nearDistanceMeters = nearDistanceMeters
        self.farDistanceMeters = farDistanceMeters
        self.failedScanMinFrameCount = failedScanMinFrameCount
        self.failedScanDismissDelaySeconds = failedScanDismissDelaySeconds
        self.maxICPIterations = maxICPIterations
        self.icpTolerance = icpTolerance
        self.bplyExportEnabled = bplyExportEnabled
        self.decoupledRenderingEnabled = decoupledRenderingEnabled
    }

    public static let `default` = ScanningConfiguration()

    public var activeDepthResolution: Int {
        useFullResolutionDepthFrames ? highResDepthResolution : lowResDepthResolution
    }
}

#endif
