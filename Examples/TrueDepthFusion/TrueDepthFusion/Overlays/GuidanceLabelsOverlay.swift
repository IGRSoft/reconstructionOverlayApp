//
//  GuidanceLabelsOverlay.swift

import SwiftUI

struct GuidanceLabelsOverlay: View {
    let isPreparing: Bool
    let isScanning: Bool
    let distanceMessage: String?

    var body: some View {
        GeometryReader { proxy in
            let ovalH = proxy.size.height * 0.72
            let ovalTop = (proxy.size.height - ovalH) / 2
            let centerY = ovalTop + ovalH / 2

            if !isScanning, !isPreparing {
                VStack(spacing: 10) {
                    Text("Center your face\nin the oval")
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(10)
                        .opacity(isScanning ? 0 : 1)
                        .animation(.easeInOut(duration: 0.4), value: isScanning)

                    if let msg = distanceMessage {
                        Text(msg)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.45))
                            .cornerRadius(10)
                    }
                }
                .frame(maxWidth: 200)
                .position(x: proxy.size.width / 2, y: centerY)
            }
        }
        .allowsHitTesting(false)
    }
}
