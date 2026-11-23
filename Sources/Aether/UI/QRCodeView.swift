import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Razor-sharp CoreImage QR code generator for instant Wi-Fi sharing (`WIFI:T:WPA;S:...;P:...;;`).
struct WiFiQRCodeCard: View {
    let ssid: String
    let payload: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("SCAN TO JOIN WI-FI")
                        .font(.system(size: 8.4, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.76))
                        .tracking(0.5)
                    Text(ssid)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let img = renderQRImage(from: payload) {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 148, height: 148)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text("Point any phone camera to connect · Clears when closed")
                .font(.system(size: 9.0))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func renderQRImage(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
