//
//  ScanControls.swift
//
//  HUD overlay for ScanningView: shutter, duration slider, elapsed timer,
//  scan-failed message, latest-scan thumbnail button.

import SwiftUI

struct ScanControls: View {
    @ObservedObject var session: ScanningSession
    let latestScanThumbnail: UIImage?
    let onShowLatestScan: () -> Void
    let onDone: () -> Void

    private var tapToStartStop: Bool {
        UserDefaults.standard.bool(forKey: "tap_to_start_stop")
    }

    var body: some View {
        ZStack {
            // Scan failed overlay
            if session.showScanFailed {
                Text("Scan failed")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // Countdown label (centered)
            if session.countdownSeconds > 0 {
                Text("\(session.countdownSeconds)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            VStack {
                // Top row: elapsed / duration
                HStack {
                    if session.scanning {
                        Text("\(session.elapsedSeconds + 1)")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .padding(.leading, 20)
                    }
                    Spacer()
                    if !tapToStartStop {
                        Text("\(session.scanDurationSeconds) sec")
                            .foregroundStyle(.white)
                            .padding(.trailing, 20)
                    }
                }
                .padding(.top, 60)

                // Duration slider (hidden while scanning or in tap-to-start-stop mode)
                if !session.scanning && !tapToStartStop {
                    Slider(value: Binding(
                        get: { Double(session.scanDurationSeconds) },
                        set: { session.setScanDuration(Int($0)) }
                    ), in: 1...20, step: 1)
                    .padding(.horizontal, 20)
                    .accentColor(.white)
                }

                Spacer()

                // Bottom row: latest scan thumbnail | shutter | done
                HStack(alignment: .center) {
                    // Latest scan thumbnail button
                    Button(action: onShowLatestScan) {
                        if let img = latestScanThumbnail {
                            Image(uiImage: img)
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
                    .padding(.leading, 24)

                    Spacer()

                    // Shutter button
                    Button(action: { session.shutterTapped() }) {
                        Image(session.scanning ? "CameraButtonRecording" : "CameraButton")
                            .resizable()
                            .frame(width: 72, height: 72)
                    }

                    Spacer()

                    // Done button
                    Button("Done", action: onDone)
                        .foregroundStyle(.white)
                        .padding(.trailing, 24)
                }
                .padding(.bottom, 40)
            }
        }
    }
}
