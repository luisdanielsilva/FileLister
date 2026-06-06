import SwiftUI

struct PhotoSettingsView: View {
    @ObservedObject private var prefs = PhotoPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Duplicate Photos").font(.title3).fontWeight(.bold)
            Text("Best-copy priority")
                .font(.headline)
            Text("When a group of similar photos is found, the keeper is chosen by these rules in order — the first rule that distinguishes two photos wins. Drag to reorder.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(Array(prefs.bestCopyPriority.enumerated()), id: \.element) { index, criterion in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                            .frame(width: 18)
                        Image(systemName: criterion.icon).foregroundColor(.indigo).frame(width: 20)
                        Text(criterion.label)
                        Spacer()
                        Image(systemName: "line.3.horizontal").foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    prefs.bestCopyPriority.move(fromOffsets: from, toOffset: to)
                }
            }
            .frame(height: 230)
            .border(Color.gray.opacity(0.2))

            Text("Changes apply immediately — keepers in the current results are re-picked automatically.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 440, height: 380)
    }
}
