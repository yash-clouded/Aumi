import SwiftUI

struct SMSComposeView: View {
    @State private var recipient: String = ""
    @State private var message: String = ""
    @State private var isSending: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("New Message")
                .font(.headline)
            
            TextField("To: Phone Number", text: $recipient)
                .textFieldStyle(.roundedBorder)
            
            TextEditor(text: $message)
                .frame(height: 100)
                .border(Color.secondary.opacity(0.2), width: 1)
                .cornerRadius(8)
            
            HStack {
                Spacer()
                Button("Cancel") {
                    // Close logic
                }
                .buttonStyle(.bordered)
                
                Button(action: sendSMS) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(recipient.isEmpty || message.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    func sendSMS() {
        isSending = true
        let payload: [String: Any] = [
            "type": "SMS_SEND",
            "recipient": recipient,
            "body": message
        ]
        
        // AumiNetworkManager.shared.sendMessage(payload)
        print("Sending SMS to \(recipient): \(message)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSending = false
            message = ""
        }
    }
}
