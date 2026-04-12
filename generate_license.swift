import Foundation
import CryptoKit

// FileLister License Generator
// Run this script to generate valid keys for your application.
// Usage: swift generate_license.swift <12-char-seed>

let salt = "FileLister-Secret-Salt-2026-Porto"

func generateKey(seed: String) -> String {
    let cleanSeed = seed.uppercased().replacingOccurrences(of: "-", with: "")
    let inputString = cleanSeed + salt
    let inputData = Data(inputString.utf8)
    let hashed = SHA256.hash(data: inputData)
    let signature = hashed.compactMap { String(format: "%02X", $0) }.joined().prefix(4)
    
    let s = cleanSeed
    return "\(s.prefix(4))-\(s.dropFirst(4).prefix(4))-\(s.dropFirst(8).prefix(4))-\(signature)"
}

// Generate a random seed if none provided
let arguments = CommandLine.arguments
if arguments.count < 2 {
    let randomSeed = (0..<12).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! }
    let seedStr = String(randomSeed)
    print("\n🎫 Generated Random License Key:")
    print("--------------------------------")
    print(generateKey(seed: seedStr))
    print("--------------------------------\n")
} else {
    let seedStr = arguments[1]
    if seedStr.count != 12 {
        print("Error: Seed must be exactly 12 characters.")
    } else {
        print("\n🎫 License Key for seed '\(seedStr)':")
        print("--------------------------------")
        print(generateKey(seed: seedStr))
        print("--------------------------------\n")
    }
}
