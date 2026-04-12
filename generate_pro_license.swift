import Foundation
import CryptoKit
import AppKit

// FileLister Pro License Generator & Automation
// This script generates a 24-char key and opens your mail client.
// Usage: swift generate_pro_license.swift "John Doe" "john@example.com"

let salt = "FileLister-Secret-Salt-2026-Porto"

func generateKey() -> String {
    // Generate 20 random uppercase/number characters (5 groups of 4)
    let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    let seed = (0..<20).map { _ in String(letters.randomElement()!) }.joined()
    
    // Calculate the 4-char signature from the 20-char seed
    let inputData = Data((seed + salt).utf8)
    let hashed = SHA256.hash(data: inputData)
    let signature = hashed.compactMap { String(format: "%02X", $0) }.joined().prefix(4)
    
    // Format: XXXX-XXXX-XXXX-XXXX-XXXX-SIG4
    var formatted = ""
    for i in 0..<5 {
        let start = seed.index(seed.startIndex, offsetBy: i*4)
        let end = seed.index(start, offsetBy: 4)
        formatted += seed[start..<end] + "-"
    }
    formatted += signature
    return formatted
}

func openEmail(name: String, email: String, key: String) {
    let subject = "Your FileLister Pro License Key".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let body = """
    Hello \(name),
    
    Thank you for purchasing FileLister!
    
    Your Pro License Key is: \(key)
    
    To activate:
    1. Open FileLister.
    2. Go to the menu FileLister > License Key...
    3. Enter your Name and this Key.
    
    Enjoy your duplicate-free Mac!
    - The FileLister Team
    """.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    
    let urlString = "mailto:\(email)?subject=\(subject)&body=\(body)"
    if let url = URL(string: urlString) {
        NSWorkspace.shared.open(url)
        print("📨 Mail client opened for \(email)")
    }
}

// Main Logic
let arguments = CommandLine.arguments
if arguments.count < 3 {
    print("❌ Usage: swift generate_pro_license.swift \"Name\" \"Email\"")
    print("Example: swift generate_pro_license.swift \"Luís Silva\" \"luis@example.com\"")
} else {
    let name = arguments[1]
    let email = arguments[2]
    let key = generateKey()
    
    print("\n--------------------------------------------------")
    print("🎫 PRO LICENSE GENERATED FOR: \(name)")
    print("📧 EMAIL: \(email)")
    print("🔑 KEY: \(key)")
    print("--------------------------------------------------\n")
    
    openEmail(name: name, email: email, key: key)
}
