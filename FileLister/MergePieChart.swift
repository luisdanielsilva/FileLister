import SwiftUI
import Charts

// Composition of a merge: what gets removed, moved, and kept (size + file count).
struct MergeComposition {
    var removedBytes: Int64 = 0   // duplicate copies trashed (space reclaimed)
    var movedBytes: Int64 = 0     // unique files moved into the kept folder
    var keptBytes: Int64 = 0      // content already in the kept folder (retained)
    var removedCount: Int = 0
    var movedCount: Int = 0
    var keptCount: Int = 0

    // The merged folder as it will look after cleaning = moved + kept.
    var resultBytes: Int64 { movedBytes + keptBytes }
    var resultCount: Int { movedCount + keptCount }
    var isEmpty: Bool { removedCount + movedCount + keptCount == 0 }

    var slices: [(label: String, bytes: Int64, count: Int, color: Color)] {
        [("Removed duplicates", removedBytes, removedCount, .red),
         ("Unique files", movedBytes, movedCount, .blue),
         ("Kept files", keptBytes, keptCount, .green)]
    }
}

// Donut chart (sized by file count) + legend with per-category file count and size,
// and a "Result" total describing the merged folder after cleaning.
struct MergePieChart: View {
    let composition: MergeComposition

    var body: some View {
        let entries = composition.slices.filter { $0.count > 0 }
        if entries.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 16) {
                Chart(entries, id: \.label) { s in
                    SectorMark(angle: .value("Files", s.count), innerRadius: .ratio(0.55), angularInset: 1.5)
                        .foregroundStyle(s.color)
                        .cornerRadius(2)
                }
                .chartLegend(.hidden)
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(entries, id: \.label) { s in
                        HStack(spacing: 6) {
                            Circle().fill(s.color).frame(width: 8, height: 8)
                            Text(s.label).font(.system(size: 11))
                            Spacer(minLength: 12)
                            Text("\(fileCount(s.count)) · \(cloudByteString(s.bytes))")
                                .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        }
                    }
                    Divider().padding(.vertical, 1)
                    HStack(spacing: 6) {
                        Text("Result").font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 12)
                        Text("\(fileCount(composition.resultCount)) · \(cloudByteString(composition.resultBytes))")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(width: 250)
            }
        }
    }

    private func fileCount(_ n: Int) -> String { "\(n) file\(n == 1 ? "" : "s")" }
}

// MARK: - Composition from merge models

// Mirrors the actual merge: every file in the kept folder is retained (incl. any
// internal duplicates); the other folders' copies are trashed; unique-to-other
// files are moved into keep. (Not the reclaimable "one per content" model.)
func mergeComposition(_ g: FolderDuplicateGroup) -> MergeComposition {
    var c = MergeComposition()
    let moveIDs = Set(g.filesToMove.map { $0.id })
    let matchedFiles = g.matchedGroups.flatMap { $0.files }
    let removed = matchedFiles.filter { $0.path != g.keepFolder && !moveIDs.contains($0.id) }
    let keptShared = matchedFiles.filter { $0.path == g.keepFolder }
    c.removedCount = removed.count
    c.removedBytes = Int64(removed.reduce(0) { $0 + $1.sizeBytes })
    c.movedCount = g.filesToMove.count
    c.movedBytes = Int64(g.filesToMove.reduce(0) { $0 + $1.sizeBytes })
    c.keptCount = g.uniqueToKeep.count + keptShared.count
    c.keptBytes = Int64(g.uniqueToKeep.reduce(0) { $0 + $1.sizeBytes }) + Int64(keptShared.reduce(0) { $0 + $1.sizeBytes })
    return c
}

func mergeComposition(_ groups: [FolderDuplicateGroup]) -> MergeComposition {
    groups.reduce(into: MergeComposition()) { acc, g in acc.add(mergeComposition(g)) }
}

func mergeComposition(_ g: CloudFolderDupGroup) -> MergeComposition {
    var c = MergeComposition()
    let moveIDs = Set(g.filesToMove.map { $0.id })
    let removed = g.matchedGroups.flatMap { $0.files }.filter { $0.path != g.keepFolder && !moveIDs.contains($0.id) }
    c.removedCount = removed.count
    c.removedBytes = removed.reduce(Int64(0)) { $0 + $1.size }
    c.movedCount = g.filesToMove.count
    c.movedBytes = g.filesToMove.reduce(Int64(0)) { $0 + $1.size }
    c.keptBytes = g.keptBytes      // every file already in the kept folder is retained
    c.keptCount = g.keptCount
    return c
}

func mergeComposition(_ groups: [CloudFolderDupGroup]) -> MergeComposition {
    groups.reduce(into: MergeComposition()) { acc, g in acc.add(mergeComposition(g)) }
}

// "Clean All Duplicates": one copy of each group is kept, the rest are erased
// (reclaimed). No files are moved, so the pie shows erased vs. kept.
func cleanComposition(_ groups: [DuplicateGroup], deleted: Set<String>) -> MergeComposition {
    var c = MergeComposition()
    for g in groups {
        let live = g.files.filter { !deleted.contains($0.fullPath) }
        guard live.count > 1 else { continue }
        let removable = live.count - 1
        c.removedCount += removable
        c.removedBytes += Int64(g.sizeBytes) * Int64(removable)
        c.keptCount += 1
        c.keptBytes += Int64(g.sizeBytes)
    }
    return c
}

private extension MergeComposition {
    mutating func add(_ o: MergeComposition) {
        removedBytes += o.removedBytes; movedBytes += o.movedBytes; keptBytes += o.keptBytes
        removedCount += o.removedCount; movedCount += o.movedCount; keptCount += o.keptCount
    }
}
