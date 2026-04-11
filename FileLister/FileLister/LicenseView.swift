import SwiftUI

struct LicenseView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var licenseManager: LicenseManager
    @State private var inputKey: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 5) {
                Text("Enter License Key")
                    .font(.headline)
                Text("Format: XXXX-YYYY-ZZZZ-WWWW")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            TextField("ABCD-1234-EFGH-5678", text: $inputKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 250)
            
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(isError ? .red : .green)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Button("Activate") {
                    if licenseManager.register(key: inputKey) {
                        statusMessage = "Application successfully registered!"
                        isError = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isPresented = false
                        }
                    } else {
                        statusMessage = "Invalid key format."
                        isError = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputKey.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 350)
    }
}
