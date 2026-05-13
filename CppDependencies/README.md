# Vendored C++ Dependencies

Each subdirectory here is a self-contained Swift Package wrapping a third-party C++ library. The libraries themselves are vendored upstream code — the project only owns the `Package.swift` shim, not the library implementations. For upstream documentation, follow the project links below.

For how these packages plug into the SDK, see [../ARCHITECTURE.md](../ARCHITECTURE.md). For adding a new dependency, see [../CONTRIBUTING.md](../CONTRIBUTING.md#adding-a-new-c-dependency).

## Index

| Package | Upstream | Purpose | Consumed by |
|---|---|---|---|
| **Eigen** | [eigen.tuxfamily.org](https://eigen.tuxfamily.org) | Header-only C++ linear algebra (matrices, vectors, decompositions) | `scsdk` |
| **PoissonRecon** | [github.com/mkazhdan/PoissonRecon](https://github.com/mkazhdan/PoissonRecon) | Screened Poisson surface reconstruction from oriented point clouds | `scsdk`, `StandardCyborgFusion` |
| **SparseICP** | [github.com/OpenGP/sparseicp](https://github.com/OpenGP/sparseicp) | Sparse Iterative Closest Point registration | `scsdk` |
| **happly** | [github.com/nmwsharp/happly](https://github.com/nmwsharp/happly) | Header-only PLY mesh I/O | `scsdk` |
| **json** | [github.com/nlohmann/json](https://github.com/nlohmann/json) | Header-only JSON for Modern C++ | `scsdk`, `StandardCyborgFusion` |
| **nanoflann** | [github.com/jlblancoc/nanoflann](https://github.com/jlblancoc/nanoflann) | Header-only k-d tree for fast nearest-neighbor lookups | `scsdk` |
| **stb** | [github.com/nothings/stb](https://github.com/nothings/stb) | Header-only image / utility libraries (image load/write etc.) | `scsdk` |
| **tinygltf** | [github.com/syoyo/tinygltf](https://github.com/syoyo/tinygltf) | Header-only glTF 2.0 loader/saver | `scsdk` |

Verify the dependency wiring against [`../scsdk/Package.swift`](../scsdk/Package.swift) and [`../Package.swift`](../Package.swift) — those files are authoritative.

## Layout convention

Each package follows the same minimal pattern:

- `Package.swift` — declares one library product and one target with `publicHeadersPath: "include"`.
- `include/` — the public header tree.
- `Sources/` *(when the library has compiled sources rather than headers only)*.
- `LICENSE` (or `LICENSE.MIT`, `COPYING`) — preserved from upstream.
- `spm_hack_generate_object_file.m` *(in some packages)* — a tiny Objective-C source whose only purpose is to give SPM something to compile when the rest of the target is header-only. SPM otherwise refuses to produce a library target with no compiled translation units.

## Licenses

Each package retains its upstream license. Per-package license files:

- `Eigen/` — see upstream (MPL2-licensed)
- `PoissonRecon/` — see upstream
- `SparseICP/` — see upstream
- `happly/LICENSE`
- `json/LICENSE.MIT`
- `nanoflann/LICENSE`
- `stb/LICENSE`
- `tinygltf/LICENSE`

The `CppDependencies/LICENSE` file at this level applies to the SPM packaging shims (`Package.swift`, the object-file hack), not the upstream libraries.
