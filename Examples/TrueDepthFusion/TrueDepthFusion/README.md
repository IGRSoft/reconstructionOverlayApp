# TrueDepthFusion — Example iOS App

Reference app demonstrating how to consume `StandardCyborgSDK` from an iOS application. It scans a face using the front-facing TrueDepth camera, fuses depth frames into a 3D point cloud, optionally meshes it, and exports the result as a PLY (or uploads it to a Jetson receiver). User-facing app behavior is documented in the [top-level README](../../../README.md).

## Building

```sh
open Examples/TrueDepthFusion/TrueDepthFusion.xcodeproj
```

- Select the **`TrueDepthFusion`** scheme.
- Choose a real iPhone with a TrueDepth front camera (iPhone X or later) as the run destination. **The simulator is not supported** — TrueDepth depth data is unavailable there.
- Press Run.

The project depends on `StandardCyborgSDK` via Swift Package Manager (resolved against the package at the repo root). The first build resolves the path dependencies and compiles `scsdk` and the C++ libraries under `CppDependencies/`.

> **Note:** The project also contains schemes for `VisualTesterMac`, `StandardCyborgAlgorithmsTestbed`, and `All-iOS-*` / `All-Mac-*`. Those targets are no longer in the project and will fail to build — use the `TrueDepthFusion` scheme.

## What the app demonstrates

The on-device flow exercises the full SDK surface:

- Live framing with a distance/oval guide.
- Lock-exposure capture from `AVCaptureDevice` (`CameraManager.swift`).
- Real-time depth-frame fusion via `StandardCyborgFusion` (`ScanningViewController.swift`, `ScanningViewRendering/`).
- Mesh generation via Poisson reconstruction (`ScanPreviewViewController.swift`).
- PLY export, including optional binary-PLY raw-frame dump (`BPLYDepthDataAccumulator.h/.mm`, `BPLYScanningViewController.swift`).
- Optional Jetson upload over the local network (`JetsonUploader.swift`).

## Exporting scans

After a scan, tap **Done** and choose:

- **Mesh** — runs Poisson surface reconstruction and previews the mesh; can be exported as a PLY.
- **Share / AirDrop** — copies the saved scan off-device.
- **Jetson upload** — sends the scan to a [`jetson_receiver`](https://github.com/josh-overlay/jetson_receiver) instance on the same network (configure the IP in app settings).

For raw frame-by-frame capture (used when iterating on the reconstruction algorithm), enable **"Dump raw frame to binary PLY"** in app settings before scanning. The resulting binary-PLY sequence is written to the app's Documents directory and can be retrieved via Finder when the device is connected over USB.

## See also

- [../../../README.md](../../../README.md) — full app overview, scanning UX, distance guidance
- [../../../ARCHITECTURE.md](../../../ARCHITECTURE.md) — SDK package layout
- [../../../CONTRIBUTING.md](../../../CONTRIBUTING.md) — development workflow
