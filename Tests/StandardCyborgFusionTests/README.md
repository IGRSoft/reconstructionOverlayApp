# StandardCyborgFusionTests

Unit tests for the `StandardCyborgFusion` target.

## Running the tests

From the repo root:

```sh
swift test
```

The test target is declared in the root [`Package.swift`](../../Package.swift) and pulls fixture data from `Tests/StandardCyborgFusionTests/Data/` via the `resources: [.copy("StandardCyborgFusionTests/Data")]` directive.

## Running from Xcode

```sh
open Package.swift
```

Then select the `StandardCyborgFusionTests` scheme and press `⌘U`. The test target's `headerSearchPath` entries mirror the `Sources/` target — see [`Package.swift`](../../Package.swift) and [ARCHITECTURE.md](../../ARCHITECTURE.md#header-search-paths) if a new C++/Obj-C++ test source fails to find its includes.

## See also

- [../../CONTRIBUTING.md](../../CONTRIBUTING.md) — dev workflow
- [../../ARCHITECTURE.md](../../ARCHITECTURE.md) — package layout
