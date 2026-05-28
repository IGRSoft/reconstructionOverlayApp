//
//  ScanControls.swift
//
//  HUD overlay for ScanningView: shutter, duration slider, elapsed timer,
//  scan-failed message, latest-scan thumbnail button.

import StandardCyborgCapture
import SwiftUI

struct ScanControls: View {
    @ObservedObject var session: ScanningSession
    let latestScanThumbnail: Image?
    var tapToStartStop: Bool = false
    let onShowLatestScan: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            FailedBanner(show: session.showScanFailed)

            CountdownText(seconds: session.countdownSeconds)

            VStack {
                HStack {
                    ElapsedText(scanning: session.scanning, elapsed: session.elapsedSeconds)
                    Spacer()
                    DurationLabel(visible: !tapToStartStop, seconds: session.scanDurationSeconds)
                }
                .padding(.top, 60)

                if !session.scanning && !tapToStartStop {
                    DurationSlider(
                        value: session.scanDurationSeconds,
                        onChange: { session.setScanDuration($0) }
                    )
                }

                Spacer()

                HStack(alignment: .center) {
                    Button(action: onShowLatestScan) {
                        ThumbnailButton(image: latestScanThumbnail)
                    }
                    .padding(.leading, 24)

                    Spacer()

                    ShutterButton(
                        scanning: session.scanning,
                        action: { session.shutterTapped() }
                    )

                    Spacer()

                    Button("Done", action: onDone)
                        .foregroundStyle(.white)
                        .padding(.trailing, 24)
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Subviews
//
// Each subview takes only the values it needs. SwiftUI's stored-property diff
// then skips body re-evaluation when ScanControls re-runs for an unrelated
// session publish.

private struct FailedBanner: View, Equatable {
    let show: Bool

    var body: some View {
        if show {
            Text("Scan failed")
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct CountdownText: View, Equatable {
    let seconds: Int

    var body: some View {
        if seconds > 0 {
            Text("\(seconds)")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(.white)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct ElapsedText: View, Equatable {
    let scanning: Bool
    let elapsed: Int

    var body: some View {
        if scanning {
            Text("\(elapsed + 1)")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.leading, 20)
        }
    }
}

private struct DurationLabel: View, Equatable {
    let visible: Bool
    let seconds: Int

    var body: some View {
        if visible {
            Text("\(seconds) sec")
                .foregroundStyle(.white)
                .padding(.trailing, 20)
        }
    }
}

private struct DurationSlider: View {
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        Slider(value: Binding(
            get: { Double(value) },
            set: { onChange(Int($0)) }
        ), in: 1...20, step: 1)
        .padding(.horizontal, 20)
        .accentColor(.white)
    }
}

private struct ShutterButton: View {
    let scanning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(scanning ? "CameraButtonRecording" : "CameraButton")
                .resizable()
                .frame(width: 72, height: 72)
        }
    }
}

private struct ThumbnailButton: View {
    let image: Image?

    var body: some View {
        if let img = image {
            img
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: 48, height: 48)
        }
    }
}
