# Contributing

Day-to-day workflow for hacking on `StandardCyborgSDK` and the `TrueDepthFusion` example app. For the package layout itself, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Prerequisites

- macOS with **Xcode 15 or later** (the toolchain must include Swift 6 — `Package.swift` declares `swift-tools-version: 6.0` and `swiftLanguageModes: [.v6]`).
- For device builds: an **iPhone with a TrueDepth front camera** (iPhone X or later). The example app cannot run in the iOS simulator — TrueDepth depth data is unavailable there.
- For Jetson upload integration (optional): a Jetson Nano running [`jetson_receiver`](https://github.com/josh-overlay/jetson_receiver) on the same Wi-Fi network as the device.

## Cloning

```sh
git clone <repo-url>
cd <repo>
```

There are no Git submodules. All nested packages (`scsdk/`, `CppDependencies/*`) are checked into the repository as path dependencies.

## Building the SDK

From the repository root:

```sh
swift build
```

This resolves the path dependencies, compiles `scsdk`, the eight `CppDependencies/*` targets, and the root `StandardCyborgFusion` target.

To work on the SDK in Xcode:

```sh
open Package.swift
```

## Running tests

```sh
swift test
```

Resource files under `Tests/StandardCyborgFusionTests/Data` are copied into the test bundle automatically via the `resources: [.copy(...)]` directive in `Package.swift`.

For Xcode-based debugging: `open Package.swift`, select the `StandardCyborgFusionTests` scheme, and press `⌘U`.

## Building the example app

The example app lives in its own Xcode project under `Examples/TrueDepthFusion/`:

```sh
open Examples/TrueDepthFusion/TrueDepthFusion.xcodeproj
```

The active scheme is **`TrueDepthFusion`** — select a real iPhone with TrueDepth and run.

Several legacy schemes (`VisualTesterMac`, `StandardCyborgAlgorithmsTestbed`, `All-iOS-Debug`/`Release`, `All-Mac-Debug`/`Release`) are still present in `xcshareddata/xcschemes/` but their underlying targets are no longer in the project — they will fail to build. Treat them as historical artifacts pending cleanup.

The project consumes `StandardCyborgSDK` as a Swift Package dependency, so any change you make to the SDK rebuilds when the example app builds.

## Modifying a `CppDependencies/*` package

Edits to any nested package take effect immediately on the next build at the root — there's no version bump or `Package.resolved` refresh needed for path dependencies. Just edit the files under `CppDependencies/<name>/` and run `swift build`.

If you change a vendored library's public headers, both `scsdk` and the root SDK rebuild on the next compile.

## Adding a new C++ dependency

1. Drop the upstream sources under `CppDependencies/<NewLibName>/`.
2. Add a `Package.swift` next to them. The pattern across existing packages is:

   ```swift
   // swift-tools-version:6.0
   import PackageDescription

   let package = Package(
       name: "NewLibName",
       products: [
           .library(name: "NewLibName", targets: ["NewLibName"]),
       ],
       targets: [
           .target(
               name: "NewLibName",
               path: ".",                  // or "Sources" if you split sources/headers
               publicHeadersPath: "include"
           ),
       ],
       cxxLanguageStandard: .cxx17
   )
   ```

3. Wire the new package into either `scsdk/Package.swift` (if it's pure-C++ and consumed by the core) or the root `Package.swift` (if it's consumed at the Fusion layer):
   - Add to the `dependencies: [.package(path: "...")]` array.
   - Add the product name to the consuming target's `dependencies: [...]` list.
4. If the library needs a new include path, add a `.headerSearchPath(...)` to the consuming target's `cxxSettings`.
5. Add an entry to [CppDependencies/README.md](CppDependencies/README.md) so the vendored-library index stays current.

## Code style and commits

This repo doesn't currently ship a formatter config. Match the surrounding style of the file you're editing. Keep commit messages focused on the *why* — see existing `git log` for tone.

## See also

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the packages fit together
- [ARCHITECTURE.md](ARCHITECTURE.md) — migration context for the pre-split structure
