import SwiftUI

struct SMSComposeView: View {
    @State private var recipient = ""
    @State private var message = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            TextField("To:", text: $recipient)
                .textFieldStyle(.roundedBorder)
            
            TextEditor(text: $message)
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Send") {
                    ConnectionManager.shared.sendControl([
                        "type": "SMS_SEND",
                        "recipient": recipient,
                        "content": message
                    ])
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
