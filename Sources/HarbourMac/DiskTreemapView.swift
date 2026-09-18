import SwiftUI
import AppKit
import HarbourCore

/// Presentation snapshot deliberately independent of diskRows (which can contain
/// overlapping recursive large_files and user-filtered results).
struct DiskTreemapContent {
    let entries: [DiskEntry]
    let map: DiskTreemap
    let scopeNote = "面積只按本次回傳的正大小子項目比例，不代表整個磁碟或可用空間；不受搜尋、大型檔案及名稱排序影響。零大小／無效大小與細小項目可在地圖清單查看。"

    init(report: DiskReport) {
        // Match the core's path identity rule, including in the fallback list.
        var unique: [String: DiskEntry] = [:]
        for entry in report.entries ?? [] {
            if let previous = unique[entry.path], previous.size >= entry.size { continue }
            unique[entry.path] = entry
        }
        entries = unique.values.sorted {
            $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size
        }
        map = DiskTreemap(items: entries.map { TreemapItem(path: $0.path, size: $0.size) })
    }
}

enum DiskTreemapInteraction {
    /// Closure seam tests routing without launching an engine or touching files.
    static func open(_ entry: DiskEntry, busy: Bool, analyze: (String) -> Void) {
        guard !busy, entry.is_dir == true else { return }
        analyze(entry.path)
    }
}

struct DiskTreemapView: View {
    @ObservedObject var model: AppModel
    let report: DiskReport
    @State private var listExpanded = false

    var body: some View {
        let content = DiskTreemapContent(report: report)
        let byPath = Dictionary(uniqueKeysWithValues: content.entries.map { ($0.path, $0) })
        return GroupBox("空間地圖（唯讀）") {
            VStack(alignment: .leading, spacing: 8) {
                Text(content.scopeNote).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(report.path).font(.caption).lineLimit(1).truncationMode(.middle).help(report.path)
                if content.map.nodes.isEmpty {
                    Text("沒有可繪製的正大小項目。").foregroundColor(.secondary).padding(.vertical, 16)
                } else {
                    GeometryReader { geometry in
                        let tiles = content.map.layout(in: TreemapFrame(
                            x: 0, y: 0, width: Double(geometry.size.width), height: Double(geometry.size.height)))
                        ZStack(alignment: .topLeading) {
                            ForEach(tiles) { tile in
                                tileView(tile, entries: byPath)
                                    .frame(width: CGFloat(tile.frame.width), height: CGFloat(tile.frame.height))
                                    .clipped()
                                    .position(x: CGFloat(tile.frame.x + tile.frame.width / 2),
                                              y: CGFloat(tile.frame.y + tile.frame.height / 2))
                            }
                        }
                    }.frame(height: 260).clipped()
                }
                if let other = content.map.nodes.first(where: { $0.id == .other }) {
                    Text("其他：合計 \(other.items.count) 個較小項目；面積已包含全部大小，展開清單可逐項查看。")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup("地圖項目清單（\(content.entries.count) 項；不受上方篩選影響）", isExpanded: $listExpanded) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(content.entries) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name).lineLimit(1)
                                        Text(entry.path).font(.caption2).foregroundColor(.secondary)
                                            .lineLimit(1).truncationMode(.middle).help(entry.path)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text(entry.size < 0 ? "大小無效" : bytes(entry.size)).font(.caption).monospacedDigit()
                                    if entry.is_dir == true {
                                        Button("開啟") { open(entry) }.disabled(model.runner.busy)
                                            .accessibilityLabel("開啟資料夾 \(entry.name)")
                                    }
                                    Button("Finder") { reveal(entry) }
                                        .accessibilityLabel("在 Finder 顯示 \(entry.name)")
                                }
                            }
                        }.padding(.vertical, 6)
                    }.frame(maxHeight: 240)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func tileView(_ tile: TreemapTile, entries: [String: DiskEntry]) -> some View {
        switch tile.id {
        case .path(let path):
            if let entry = entries[path] {
                Button {
                    if entry.is_dir == true { open(entry) } else { reveal(entry) }
                } label: {
                    tileLabel(tile, name: entry.name, detail: bytes(entry.size),
                              color: entry.is_dir == true ? .blue : .teal)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(entry.is_dir == true && model.runner.busy)
                .help("\(entry.name) · \(bytes(entry.size))")
                .accessibilityLabel("\(entry.is_dir == true ? "開啟資料夾" : "在 Finder 顯示") \(entry.name)，\(bytes(entry.size))")
                .contextMenu {
                    if entry.is_dir == true {
                        Button("開啟資料夾") { open(entry) }.disabled(model.runner.busy)
                    }
                    Button("在 Finder 顯示") { reveal(entry) }
                }
            }
        case .other:
            Button { listExpanded = true } label: {
                tileLabel(tile, name: "其他", detail: "\(tile.node.items.count) 項", color: .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("其他 \(tile.node.items.count) 項；展開地圖清單")
            .help("其他 \(tile.node.items.count) 項，點按展開清單")
        }
    }

    private func tileLabel(_ tile: TreemapTile, name: String, detail: String, color: Color) -> some View {
        ZStack {
            Rectangle().fill(color.opacity(0.22))
            // No insets/minimum tile sizes: the geometry retains true size ratios.
            Path { path in
                path.addRect(CGRect(x: 0, y: 0, width: CGFloat(tile.frame.width), height: CGFloat(tile.frame.height)))
            }.stroke(Color.primary.opacity(0.3), lineWidth: 1)
            if tile.frame.width >= 65 && tile.frame.height >= 34 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.caption).lineLimit(1).truncationMode(.middle)
                    if tile.frame.height >= 52 { Text(detail).font(.caption2).lineLimit(1) }
                }.padding(5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.contentShape(Rectangle())
    }

    private func open(_ entry: DiskEntry) {
        DiskTreemapInteraction.open(entry, busy: model.runner.busy) { model.analyze($0) }
    }

    private func reveal(_ entry: DiskEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
    }
}
