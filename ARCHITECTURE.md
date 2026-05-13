# Architecture

This document describes the modular Swift Package Manager (SPM) layout of the repository. For app features and end-user behavior, see the top-level [README](README.md).

## Overview

The repository is a single Swift Package (`StandardCyborgSDK`) whose product, `StandardCyborgFusion`, depends on a layered set of nested path packages. The example app under `Examples/TrueDepthFusion/` consumes the same package as a downstream client would.

```
StandardCyborgSDK (root Package.swift)
└── StandardCyborgFusion        — Swift/Obj-C/Metal/C++ target, public API
    ├── ZipArchive              — remote SPM dep (ZipArchive/ZipArchive)
    ├── json                    — path: CppDependencies/json
    ├── PoissonRecon            — path: CppDependencies/PoissonRecon
    └── scsdk (path: scsdk/)    — pure-C++ core library
        ├── Eigen               — path: CppDependencies/Eigen
        ├── happly              — path: CppDependencies/happly
        ├── json                — path: CppDependencies/json
        ├── nanoflann           — path: CppDependencies/nanoflann
        ├── SparseICP           — path: CppDependencies/SparseICP
        ├── PoissonRecon        — path: CppDependencies/PoissonRecon
        ├── stb                 — path: CppDependencies/stb
        └── tinygltf            — path: CppDependencies/tinygltf
```

All `CppDependencies/*` packages are vendored, header-mostly C++ libraries exposed as SPM targets with `publicHeadersPath: "include"`. See [CppDependencies/README.md](CppDependencies/README.md) for the full index.

## Package Boundaries

### `StandardCyborgSDK` — root Package.swift

Owns the public, integrator-facing surface: the `StandardCyborgFusion` library (dynamic), Metal shaders, depth-frame fusion pipeline, ML model glue, and Obj-C/Swift bridging headers under `Sources/StandardCyborgFusion/`. Depends on `scsdk` for the pure-C++ algorithms, `json` and `PoissonRecon` directly (used at the Fusion layer), and `ZipArchive` for archive handling.

Test target `StandardCyborgFusionTests` lives under `Tests/` and copies the `Tests/StandardCyborgFusionTests/Data` resource bundle.

### `scsdk` — `scsdk/Package.swift`

Owns the portable, platform-agnostic C++ core under `scsdk/Sources/standard_cyborg`:

- `math` — integer containers and linear algebra
- `sc3d` — 3D geometry, imaging, selection, annotation
- `scene_graph` — portable 3D scene representation
- `algorithms` — algorithms operating on scsdk data structures
- `io` — JSON / PLY / GLTF SERDES
- `util` — supporting utilities

Knows nothing about Metal, Apple frameworks, or app-level concerns. Pulls in all eight C++ dependencies. The legacy GTest suite under `scsdk/Tests/scsdk_test` is preserved on disk but is **not** an active SPM test target (it's commented out in `scsdk/Package.swift`).

### `CppDependencies/*`

Eight vendored C++ libraries, each with its own `Package.swift` exposing a single library target. They are consumed by `scsdk` (mostly) and by the root `StandardCyborgFusion` target (for `json` and `PoissonRecon`). The repo does not maintain these libraries — see `CppDependencies/README.md` for upstream sources.

## Why the split

The repository was previously organized around a single `StandardCyborgSDK.xcodeproj` that bundled the SDK, the C++ core, the example app, and the test bench. The split delivers:

1. **No custom .xcodeproj for the SDK.** Open `Package.swift` in Xcode, or build with `swift build` from any CI runner. The example app's `.xcodeproj` is the only project file, and it consumes the SDK as a real package — the same way an external integrator would.
2. **Clear ownership boundaries.** The pure-C++ core (`scsdk`) cannot accidentally pick up Apple-framework dependencies, and the Fusion layer cannot bypass `scsdk`'s public headers.
3. **Faster, more targeted incremental builds.** Touching a single `CppDependencies/*` header invalidates only that package's consumers.
4. **Easier dependency surgery.** Replacing or upgrading a vendored library is local to its `CppDependencies/<name>/` folder.

## Header search paths

`Sources/StandardCyborgFusion/` is a hybrid Swift/Obj-C/Metal/C++ target. Because the legacy folder layout was preserved during the split, the root `Package.swift` declares explicit `headerSearchPath` entries (under `cxxSettings`) that mirror the historical include hierarchy:

```
Sources/StandardCyborgFusion/{Algorithm,DataStructures,EarLandmarking,Helpers,IO,MetalDepthProcessor,Private}
Sources/include/StandardCyborgFusion
libigl/include
```

If you add a new C++/Obj-C++ source file with includes that don't resolve, the fix is almost always one of:

- The include is relative to one of the listed search paths above — add the file in the right subdirectory and the existing entries cover it.
- The include needs a new directory — add a new `.headerSearchPath(...)` entry to **both** the `StandardCyborgFusion` target and the `StandardCyborgFusionTests` target.

The `Tests/` target mirrors the same set of header search paths via `..` prefixes; keep the two lists in sync.

## See also

- [README.md](README.md) — app overview, scanning UX, Jetson integration
- [CONTRIBUTING.md](CONTRIBUTING.md) — dev setup, building, testing
- Migration context — see the **SPM Package Split** section above for upgrade notes from the pre-split structure
- [CppDependencies/README.md](CppDependencies/README.md) — vendored-library index
