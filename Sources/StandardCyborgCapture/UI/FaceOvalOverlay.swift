//
//  FaceOvalOverlay.swift

#if os(iOS)

import SwiftUI

/// Dashed oval face-guide overlay matching ScanningViewController's CAShapeLayer.
public struct FaceOvalOverlay: View {
    public let isScanning: Bool

    public init(isScanning: Bool) {
        self.isScanning = isScanning
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width * 0.60
            let h = proxy.size.height * 0.60
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

#endif
