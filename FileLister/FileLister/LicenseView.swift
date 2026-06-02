import SwiftUI

struct LicenseView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var licenseManager: LicenseManager
    @State private var inputKey: String = ""
    @State private var inputName: String = ""
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
                    Text("Enter your name and the 24-character key.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 10) {
                    TextField("Full Name", text: $inputName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        
                    TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $inputKey)
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
                    Text(licenseManager.registeredName)
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
                        if licenseManager.register(key: inputKey, name: inputName.isEmpty ? "Premium User" : inputName) {
                            statusMessage = "Successfully registered!"
                            isError = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { isPresented = false }
                        } else {
                            statusMessage = "Invalid key format or signature."
                            isError = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputKey.isEmpty)
                } else {
                    Button("Unregister") {
                        licenseManager.deactivate()
                        statusMessage = "License removed."
                        isError = false
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
        }
        .padding(30)
        .frame(width: 380)
    }
}
