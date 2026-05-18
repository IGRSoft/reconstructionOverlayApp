//
//  FaceOvalOverlay.swift

import SwiftUI

/// Dashed oval face-guide overlay matching ScanningViewController's CAShapeLayer.
struct FaceOvalOverlay: View {
    let isScanning: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width * 0.60
            let h = proxy.size.height * 0.72
            let x = (proxy.size.width - w) / 2
            let y = (proxy.size.height - h) / 2

            Ellipse()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                .foregroundStyle(.white.opacity(isScanning ? 0.3 : 0.7))
                .frame(width: w, height: h)
                .position(x: x + w / 2, y: y + h / 2)
                .animation(.easeInOut(duration: 0.4), value: isScanning)
        }
    }
}
