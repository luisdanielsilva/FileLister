import SwiftUI

struct LicenseView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var licenseManager: LicenseManager
    @State private var inputKey: String = ""
    @State private var inputEmail: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: licenseManager.isRegistered ? "checkmark.seal.fill" : "key.fill")
                .font(.system(size: 40))
                .foregroundColor(licenseManager.isRegistered ? .green : .blue)
            
            if !licenseManager.isRegistered {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Register FileLister")
                        .font(.headline)
                    Text("Enter your email address and the 26-character key.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 10) {
                    TextField("Email Address", text: $inputEmail)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        
                    TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXXXX", text: $inputKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 250)
                }
            } else {
                VStack(spacing: 10) {
                    Text("Application Registered")
                        .font(.headline)
                    Text("Licensed to:")
                        .font(.caption).foregroundColor(.secondary)
                    Text(licenseManager.registeredEmail)
                        .font(.title3).fontWeight(.bold)
                    
                    Text(licenseManager.licenseKey)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.top, 5)
                }
            }
            
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(isError ? .red : .green)
            }
            
            HStack(spacing: 12) {
                Button(licenseManager.isRegistered ? "Close" : "Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                if !licenseManager.isRegistered {
                    Button("Activate") {
                        if licenseManager.register(key: inputKey, email: inputEmail) {
                            statusMessage = "Successfully registered!"
                            isError = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { isPresented = false }
                        } else {
                            statusMessage = "Invalid key format or signature."
                            isError = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputKey.isEmpty || inputEmail.isEmpty || !inputEmail.contains("@"))
                }
            }
        }
        .padding(30)
        .frame(width: 380)
    }
}
