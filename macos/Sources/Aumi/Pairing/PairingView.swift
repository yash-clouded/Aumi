import SwiftUI
import CoreImage.CIFilterBuiltins

/// The first-run pairing screen. Displays Aumi's QR code for Android to scan.
struct PairingView: View {
    @State private var qrImage: NSImage? = nil
    @State private var isPaired = false
    @State private var pairingStatus = "Open Aumi on your Android phone and scan this code"

    var body: some View {
        VStack(spacing: 28) {
            // Title
            VStack(spacing: 6) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.blue)
                Text("Pair with Aumi Android")
                    .font(.title2.bold())
                Text(pairingStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // QR Code
            if let qr = qrImage {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 220, height: 220)
                    .overlay(ProgressView())
            }

            // Instruction steps
            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: "1", text: "Install Aumi on your Android phone")
                StepRow(number: "2", text: "Open Aumi → tap Scan QR")
                StepRow(number: "3", text: "Point camera at the code above")
            }
            .padding(.horizontal, 40)

            if isPaired {
                Label("Paired successfully!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }
        }
        .onAppear { generateQR() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AumiConnected"))) { _ in
            self.isPaired = true
            self.pairingStatus = "Successfully Linked!"
        }
    }

    private func generateQR() {
        let localIp = getLocalIP() ?? "0.0.0.0"
        let key = PairingManager.shared.prepareNewPairing()
        let content = "aumi://pair?id=\(Host.current().localizedName ?? "Mac")&pubkey=\(key)&ip=\(localIp)&port=8765"

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        qrImage = nsImage
    }

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var ptr = ifaddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let addr  = current.pointee.ifa_addr.pointee
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING),
               addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(current.pointee.ifa_addr, socklen_t(addr.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                address = String(cString: hostname)
            }
            ptr = current.pointee.ifa_next
        }
        freeifaddrs(ifaddr)
        return address
    }
}

private struct StepRow: View {
    let number: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.blue)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        Text("Aumi Settings")
            .frame(width: 400, height: 300)
    }
}
