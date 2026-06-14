import SwiftUI

// Shared min/max file-size filter used by Files (local + remote) and Photos modes.
// Session-only — held as view @State, never persisted.
enum SizeUnit: String, CaseIterable {
    case kb = "KB", mb = "MB", gb = "GB"
    var bytes: Int64 {
        switch self {
        case .kb: return 1_024
        case .mb: return 1_048_576
        case .gb: return 1_073_741_824
        }
    }
}

struct SizeFilter {
    var minText = ""
    var maxText = ""
    var unit: SizeUnit = .mb

    var isActive: Bool { !minText.isEmpty || !maxText.isEmpty }

    // (min, max) in bytes; 0 means "no bound".
    private var bounds: (min: Int64, max: Int64) {
        let u = unit.bytes
        let lo = Int64(minText).flatMap { $0 > 0 ? $0 * u : nil } ?? 0
        let hi = Int64(maxText).flatMap { $0 > 0 ? $0 * u : nil } ?? 0
        return (lo, hi)
    }

    func contains(_ size: Int64) -> Bool {
        let (lo, hi) = bounds
        return (lo == 0 || size >= lo) && (hi == 0 || size <= hi)
    }
    func contains(_ size: Int) -> Bool { contains(Int64(size)) }

    mutating func clear() { minText = ""; maxText = "" }
}

// Compact, intrinsic-width filter controls meant to sit inline next to the
// bulk-action buttons in each results view's action row.
struct SizeFilterBar: View {
    @Binding var filter: SizeFilter

    var body: some View {
        HStack(spacing: 6) {
            Text("Size:").font(.system(size: 10)).foregroundColor(.secondary)
            TextField("min", text: $filter.minText)
                .textFieldStyle(.roundedBorder).frame(width: 52).font(.system(size: 10))
            Text("–").font(.system(size: 10)).foregroundColor(.secondary)
            TextField("max", text: $filter.maxText)
                .textFieldStyle(.roundedBorder).frame(width: 52).font(.system(size: 10))
            Picker("", selection: $filter.unit) {
                ForEach(SizeUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().frame(width: 62).controlSize(.small)
            if filter.isActive {
                Button(action: { filter.clear() }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain).help("Clear size filter")
            }
        }
    }
}
