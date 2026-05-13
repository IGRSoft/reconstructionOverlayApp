# scsdk — Portable C++ Core for 3D Perception

`scsdk` is a nested Swift Package that contains the pure-C++ core of the StandardCyborg SDK. It has no Apple-platform dependencies (no Metal, no UIKit) and is consumed by the parent `StandardCyborgFusion` target as an SPM dependency.

For the overall package layout, see [../ARCHITECTURE.md](../ARCHITECTURE.md).

## Components

Sources live under `Sources/standard_cyborg/`:

- `math` — integer containers and linear algebra primitives.
- `sc3d` — core 3D geometry, imaging, selection, annotation.
- `scene_graph` — portable representation of a complete 3D scene.
- `algorithms` — 3D-perception algorithms operating on scsdk data structures.
- `io` — SERDES across JSON, PLY, GLTF, and other formats.
- `util` — supporting utilities.

## Consuming via SPM

`scsdk` is already wired into the root [`Package.swift`](../Package.swift) as a path dependency:

```swift
.package(path: "./scsdk"),
```

Building the parent SDK with `swift build` at the repo root automatically resolves and compiles `scsdk` along with its eight `CppDependencies/*` libraries. There is nothing to install or initialize.

To consume `scsdk` from another package, depend on it via the same path or via the parent SDK rather than reaching into this directory directly — its dependency graph (`Eigen`, `happly`, `json`, `nanoflann`, `SparseICP`, `PoissonRecon`, `stb`, `tinygltf`) is non-trivial.

## Tests

The legacy GTest suite under `Tests/scsdk_test/` (with fixture data in `Tests/test_fixture_data/`) is preserved in source for reference but is **not** an active SPM test target — the `.testTarget` in [`Package.swift`](Package.swift) is currently commented out. Runtime coverage of `scsdk` happens via the parent target's tests at the repo root:

```sh
swift test
```

See [../CONTRIBUTING.md](../CONTRIBUTING.md#running-tests) for details.

## See also

- [../README.md](../README.md) — top-level project overview
- [../ARCHITECTURE.md](../ARCHITECTURE.md) — package boundaries
- [../CppDependencies/README.md](../CppDependencies/README.md) — vendored dependencies
