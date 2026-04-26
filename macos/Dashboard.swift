import SwiftUI

struct AumiDashboardView: View {
    @State private var isConnected: Bool = false
    @State private var deviceName: String = "No Device Paired"
    @State private var showSMSComposer: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 20) {
                Label("Status", systemImage: isConnected ? "link" : "link.badge.plus")
                    .foregroundColor(isConnected ? .green : .orange)
                
                Button(action: { showSMSComposer = true }) {
                    Label("Compose SMS", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)
                
                Label("Screen Mirror", systemImage: "desktopcomputer")
                Label("Files", systemImage: "folder")
                
                Spacer()
                
                Text(deviceName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(width: 180)
            .background(Color.secondary.opacity(0.1))
            
            // Main Content
            VStack {
                if !isConnected {
                    VStack(spacing: 20) {
                        Text("Pair with Aumi Android")
                            .font(.title2)
                            .bold()
                        
                        // QR Code Placeholder
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary, lineWidth: 2)
                                .frame(width: 200, height: 200)
                            
                            Image(systemName: "qrcode")
                                .resizable()
                                .padding(40)
                                .frame(width: 200, height: 200)
                        }
                        
                        Text("Scan this code in the Aumi Android app to link your devices.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                } else {
                    VStack {
                        Image(systemName: "iphone")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 100)
                            .foregroundColor(.blue)
                        
                        Text("Connected to \(deviceName)")
                            .font(.headline)
                        
                        Text("All systems operational")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 400)
        .sheet(isPresented: $showSMSComposer) {
            SMSComposeView()
        }
    }
}
