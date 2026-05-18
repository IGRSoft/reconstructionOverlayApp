// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StandardCyborgSDK",
    platforms: [
        .iOS(.v16), .macOS(.v13)
    ],
    products: [
        .library(
            name: "StandardCyborgSDK",
            type: .dynamic,
            targets: ["StandardCyborgFusion"]
        ),
        .library(
            name: "StandardCyborgCapture",
            type: .dynamic,
            targets: ["StandardCyborgCapture"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "Eigen",
            path: "CppDependencies/Eigen",
            exclude: ["Package.swift"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "happly",
            path: "CppDependencies/happly",
            exclude: ["Package.swift", "LICENSE", "README.md"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "json",
            path: "CppDependencies/json",
            exclude: ["Package.swift", "LICENSE.MIT", "README.md"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "nanoflann",
            path: "CppDependencies/nanoflann",
            exclude: ["Package.swift", "LICENSE", "README.md"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "SparseICP",
            path: "CppDependencies/SparseICP",
            exclude: ["Package.swift", "README.md"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "stb",
            path: "CppDependencies/stb",
            exclude: ["Package.swift", "LICENSE", "README.md"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "tinygltf",
            path: "CppDependencies/tinygltf",
            exclude: ["Package.swift", "LICENSE", "README.md"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "PoissonRecon",
            path: "CppDependencies/PoissonRecon/Sources",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("STD_LIB_FLAG"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
            ]
        ),
        .target(
            name: "standard_cyborg",
            dependencies: [
                "Eigen", "happly", "json", "nanoflann", "PoissonRecon", "SparseICP", "stb", "tinygltf"
            ],
            path: "scsdk/Sources/standard_cyborg",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-fobjc-arc", "-Os", "-fno-math-errno", "-ffast-math"]),
                .define("FMT_HEADER_ONLY", to: "1", .when(platforms: [.iOS, .macOS])),
                .define("HAVE_CONFIG_H", to: "1", .when(platforms: [.iOS, .macOS])),
                .define("HAVE_PTHREAD", to: "1", .when(platforms: [.iOS, .macOS])),
                .define("GUID_LIBUUID", .when(platforms: [.iOS, .macOS])),
            ]
        ),
        .target(
            name: "StandardCyborgFusion",
            dependencies: [
                "json",
                "standard_cyborg",
                "PoissonRecon",
                "ZipArchive",
            ],
            path: "Sources",
            exclude: [
                "StandardCyborgCapture",
                "StandardCyborgCaptureObjC",
            ],
            resources: [
                .process("StandardCyborgFusion/Models/SCEarLandmarking.mlmodel"),
                .process("StandardCyborgFusion/Models/SCEarTrackingModel.mlmodel"),
                .process("StandardCyborgFusion/Models/SCFootTrackingModel.mlmodel"),
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                // Always optimize, even for debug builds, in order to be usable while debugging the rest of an app
                .unsafeFlags(["-fobjc-arc", "-Os", "-fno-math-errno", "-ffast-math"]),
                .headerSearchPath("."),
                .headerSearchPath("../libigl/include"),
                .headerSearchPath("StandardCyborgFusion/Algorithm"),
                .headerSearchPath("StandardCyborgFusion/DataStructures"),
                .headerSearchPath("StandardCyborgFusion/EarLandmarking"),
                .headerSearchPath("StandardCyborgFusion/Helpers"),
                .headerSearchPath("StandardCyborgFusion/IO"),
                .headerSearchPath("StandardCyborgFusion/MetalDepthProcessor"),
                .headerSearchPath("StandardCyborgFusion/Private"),
                .headerSearchPath("include/StandardCyborgFusion"),
            ]
        ),
        .target(
            name: "StandardCyborgCaptureObjC",
            dependencies: ["StandardCyborgFusion"],
            path: "Sources/StandardCyborgCaptureObjC",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-fobjc-arc", "-Os", "-fno-math-errno", "-ffast-math"]),
                .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "StandardCyborgCapture",
            dependencies: [
                "StandardCyborgFusion",
                "StandardCyborgCaptureObjC",
            ],
            path: "Sources/StandardCyborgCapture",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "StandardCyborgFusionTests",
            dependencies: ["StandardCyborgFusion"],
            path: "Tests",
            resources: [
                .copy("StandardCyborgFusionTests/Data")
            ],
            cxxSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("PROJECT_DIR", to: "\".\""),
                .unsafeFlags(["-fobjc-arc"]),
                .headerSearchPath("."),
                .headerSearchPath("../libigl/include"),
                .headerSearchPath("../Sources/StandardCyborgFusion/Algorithm"),
                .headerSearchPath("../Sources/StandardCyborgFusion/DataStructures"),
                .headerSearchPath("../Sources/StandardCyborgFusion/Helpers"),
                .headerSearchPath("../Sources/StandardCyborgFusion/IO"),
                .headerSearchPath("../Sources/StandardCyborgFusion/MetalDepthProcessor"),
                .headerSearchPath("../Sources/StandardCyborgFusion/Private"),
                .headerSearchPath("../Sources/include/StandardCyborgFusion"),
            ],
            linkerSettings: [
                .linkedFramework("XCTest"),
            ]
        )
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
