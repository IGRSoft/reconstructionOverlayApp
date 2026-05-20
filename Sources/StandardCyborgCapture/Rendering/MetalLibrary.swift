//
//  MetalLibrary.swift
//  StandardCyborgCapture
//
//  Loads the package's Metal shader library via `Bundle.module`. Required so
//  that `StandardCyborgCapture`'s renderers can resolve their `.metal` shaders
//  no matter which app embeds the package — the bare `MTLDevice.makeDefaultLibrary()`
//  would otherwise look in the consumer app's bundle and crash at runtime.
//

#if os(iOS)

import Metal

public enum MetalLibraryError: Error, Sendable {
    /// The package's compiled Metal library was not found in `Bundle.module`.
    ///
    /// Typically indicates a build-tool regression in the consumer's Xcode
    /// toolchain — the `.metal` shaders failed to compile into the `.metallib`
    /// that ships with `StandardCyborgCapture`.
    case libraryNotFound
}

public extension MTLDevice {
    /// Loads the package's Metal shader library, compiled from
    /// `DepthColoringFilter.metal` + `SCPointCloudRenderer.metal`.
    ///
    /// Resolves the library from `Bundle.module` so it works under SPM,
    /// not the consuming app's bundle. Cache the returned `MTLLibrary`
    /// once per `MTLDevice` for the lifetime of the app.
    ///
    /// - Throws: `MetalLibraryError.libraryNotFound` if the bundle does not
    ///   contain a default Metal library.
    func makeStandardCyborgCaptureLibrary() throws -> MTLLibrary {
        do {
            return try makeDefaultLibrary(bundle: .module)
        } catch {
            throw MetalLibraryError.libraryNotFound
        }
    }
}

#endif
