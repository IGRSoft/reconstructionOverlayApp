# Migration: Pre-Split → SPM Layout

This branch (`feature/spm-package-split`) replaces the monolithic `StandardCyborgSDK.xcodeproj` with a layered Swift Package layout. This document is for contributors and downstream consumers who knew the old structure.

For the new layout in detail, see [ARCHITECTURE.md](ARCHITECTURE.md).

## What changed

- The top-level `StandardCyborgSDK.xcodeproj` is **removed**. The repository root is now a Swift Package (`Package.swift`, product `StandardCyborgSDK`, target `StandardCyborgFusion`).
- The TrueDepthFusion example app and its `.xcodeproj` (with all of its schemes) moved under `Examples/TrueDepthFusion/`. The project is now self-contained inside that folder and consumes the SDK as a Swift Package dependency.
- The pure-C++ core was extracted into a nested SPM package at `scsdk/`.
- Eight C++ dependencies were extracted into individual nested SPM packages under `CppDependencies/`.

## Path map

The following is the high-level renaming. Use `git log --follow <new-path>` to walk individual file histories.

| Old path | New path |
|---|---|
| `StandardCyborgSDK.xcodeproj/` | `Examples/TrueDepthFusion/TrueDepthFusion.xcodeproj/` |
| `StandardCyborgSDK.xcodeproj/xcshareddata/xcschemes/*.xcscheme` | `Examples/TrueDepthFusion/TrueDepthFusion.xcodeproj/xcshareddata/xcschemes/*.xcscheme` |
| `TrueDepthFusion/` (app sources, assets) | `Examples/TrueDepthFusion/TrueDepthFusion/` |
| `StandardCyborgFusion/` (SDK sources, if you had them at the root) | `Sources/StandardCyborgFusion/` |
| `StandardCyborgFusionTests/` | `Tests/StandardCyborgFusionTests/` |
| Pure-C++ core (was bundled into the framework target) | `scsdk/Sources/standard_cyborg/` |
| Vendored C++ libraries (e.g. `Eigen`, `PoissonRecon`, `nanoflann`, …) | `CppDependencies/<LibName>/` |

The shared-scheme files were carried forward unchanged, but only the **`TrueDepthFusion`** scheme has an active target in the post-split project. The legacy schemes (`VisualTesterMac`, `StandardCyborgAlgorithmsTestbed`, `All-iOS-{Debug,Release}`, `All-Mac-{Debug,Release}`) reference targets that were removed; they remain on disk but won't build until those targets are restored or the schemes are deleted.

## Migrating downstream consumers

If your project previously referenced `StandardCyborgSDK.xcodeproj` directly (added to a workspace, embedded as a sub-project, or `lipo`-ed into a binary), replace that reference with a Swift Package dependency.

### Swift Package Manager

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/<repo>", from: "1.0.0"),
    // or, for local development:
    // .package(path: "../path/to/repo"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "StandardCyborgSDK", package: "<repo>"),
        ]
    ),
]
```

The product name is `StandardCyborgSDK` (declared in the root `Package.swift`); it vends the `StandardCyborgFusion` library as a dynamic framework.

### Xcode (without an external Package.swift)

In your project: **File → Add Package Dependencies… → Add Local…** and point at the repo root, or paste the Git URL into the search box. Then add the `StandardCyborgSDK` library to your app target's "Frameworks, Libraries, and Embedded Content".

## Internal include paths

The folder layout under `Sources/StandardCyborgFusion/` was preserved during the split, so existing `#include "Algorithm/..."`, `#include "DataStructures/..."`, etc. resolve unchanged via the `headerSearchPath` entries in the root `Package.swift`. If a previously-resolving include now fails, see the **Header search paths** section of [ARCHITECTURE.md](ARCHITECTURE.md).

## Migration: scanning stack lifted into `StandardCyborgCapture`

A second restructuring (branch `feature/extract-scanning-package`) lifted the SwiftUI scanning stack from the example app into the package as two new targets:

- `StandardCyborgCaptureObjC` — ObjC++ scan data model (`Scan`, `BPLYDepthDataAccumulator`).
- `StandardCyborgCapture` — Swift capture/render/session/UI toolkit, iOS-only.

If you had copied any of the example app's scanning files into your own project, replace them with imports.

### Import swaps

| Old | New |
|---|---|
| `import TrueDepthFusionObjC` | `import StandardCyborgCaptureObjC` |
| Local copy of `CameraManager`, `ScanningSession`, `ScanStore`, `MeshingService`, `ScanningViewRenderer`, `SCPointCloudRenderer`, `DepthColoringFilter`, `MetalLayerView`, `ScanPreviewView`, `ScanPreviewSceneView`, `ScanningView`, `BPLYScanningView`, `UIImage.resized(toWidth:)` | `import StandardCyborgCapture` |
| Local copy of `AudioAndHapticEngine`, `SoundEffect`, `FaceOvalOverlay`, `ScanControls` | App-level code; implement `ScanFeedbackProvider` and inject via `ScanningView(feedbackProvider:)` |

### Public API changes from the prior example-local versions

- `ScanningViewRenderer.init(device:commandQueue:)` now `throws` (replaces force-unwrap of `device.makeDefaultLibrary()`).
- `ScanControls` gains `tapToStartStop: Bool` parameter (replacing the implicit `UserDefaults` read); `latestScanThumbnail` is now SwiftUI `Image?` (was `UIImage?`).
- `ScanPreviewView` gains required closures `onExport: (Scan, SCMesh?) -> Void` and `onShowSettings: () -> Void`; export/Jetson `.sheet` modifiers were removed (apps wire their own).
- `ScanningView` gains required closures `onExport`, `onShowSettings`, `onDone`, `onShowLatestScan` that forward to the embedded `ScanPreviewView`.

### Bundle / resource loading

Inside the package, `Bundle.module` is the resource bundle. Consumers writing custom SwiftUI views that load matcap, camera-button images, or `ScanPreviewViewController.scn` should use `Image("…", bundle: .module)` and `Bundle.module.url(forResource:withExtension:)`. The package-internal `MTLDevice.makeStandardCyborgCaptureLibrary()` helper loads the package's Metal shaders. Sound effects are no longer in the package — apps provide their own audio via `ScanFeedbackProvider`.

### `ScanPreviewHostingController` removed

The transient SwiftUI/UIKit bridge `ScanPreviewHostingController` is deleted (dead code post-SwiftUI migration). Apps using it should migrate to the SwiftUI `ScanPreviewView` directly.

## See also

- [ARCHITECTURE.md](ARCHITECTURE.md) — package boundaries and rationale
- [CONTRIBUTING.md](CONTRIBUTING.md) — building, testing, adding dependencies
