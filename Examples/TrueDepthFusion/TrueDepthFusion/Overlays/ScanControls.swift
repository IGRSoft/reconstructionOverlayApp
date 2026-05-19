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

            if session.countdownSeconds > 0 {
                Text("\(session.countdownSeconds)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            VStack {
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

                if !session.scanning && !tapToStartStop {
                    Slider(value: Binding(
                        get: { Double(session.scanDurationSeconds) },
                        set: { session.setScanDuration(Int($0)) }
                    ), in: 1...20, step: 1)
                    .padding(.horizontal, 20)
                    .accentColor(.white)
                }

                Spacer()

                HStack(alignment: .center) {
                    Button(action: onShowLatestScan) {
                        if let img = latestScanThumbnail {
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
                    .padding(.leading, 24)

                    Spacer()

                    Button(action: { session.shutterTapped() }) {
                        Image(session.scanning ? "CameraButtonRecording" : "CameraButton")
                            .resizable()
                            .frame(width: 72, height: 72)
                    }

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
