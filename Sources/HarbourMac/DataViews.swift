import SwiftUI
import AppKit

func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
func dictionary(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
func display(_ value: Any?) -> String {
    guard let value = value, !(value is NSNull) else { return "未提供" }
    return String(describing: value)
}

struct Metric: View {
    let title: String
    let value: Double?
    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value.map { String(format: "%.1f%%", $0) } ?? "未提供").font(.title2.monospacedDigit())
                if let value = value { ProgressView(value: min(100, max(0, value)), total: 100) }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Native recursive inspector keeps every metric exposed by Mole available,
// including hardware-specific fields not present on every Intel Mac.
struct JSONInspector: View {
    let value: Any
    var body: some View { content(value) }
    private func content(_ value: Any) -> AnyView {
        if let object = value as? [String: Any] {
            return AnyView(VStack(alignment: .leading, spacing: 6) {
                ForEach(object.keys.sorted(), id: \.self) { key in
                    if object[key] is [String: Any] || object[key] is [Any] {
                        DisclosureGroup(key.replacingOccurrences(of: "_", with: " ")) { content(object[key]!).padding(.leading, 10) }
                    } else {
                        HStack(alignment: .top) { Text(key.replacingOccurrences(of: "_", with: " ")).foregroundColor(.secondary); Spacer(); Text(display(object[key])).textSelection(.enabled).multilineTextAlignment(.trailing) }
                    }
                }
            })
        }
        if let list = value as? [Any] {
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                if list.isEmpty { Text("沒有資料").foregroundColor(.secondary) }
                ForEach(list.indices, id: \.self) { index in
                    GroupBox(display(dictionary(list[index])["name"] ?? dictionary(list[index])["mount"] ?? "\(index + 1)")) { content(list[index]).padding(6) }
                }
            })
        }
        return AnyView(Text(display(value)).textSelection(.enabled))
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    private let groups = [("gpu", "GPU"), ("disks", "磁碟容量與健康"), ("disk_io", "磁碟讀寫 MB/s"), ("network", "網絡 MB/s"), ("batteries", "電池"), ("thermal", "溫度與風扇"), ("sensors", "感測器"), ("bluetooth", "藍牙"), ("top_processes", "高用量程序"), ("process_alerts", "程序提示")]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("更新快照") { model.loadStatus(live: false) }.disabled(model.runner.busy)
                Button(model.watch ? "停止監察" : "持續監察（每 2 秒）") { if model.watch { model.cancel() } else { model.loadStatus(live: true) } }.disabled(model.runner.busy && !model.watch)
            }
            if model.snapshot.isEmpty { Text("按更新快照取得真實系統資料。").foregroundColor(.secondary) }
            else {
                Text(display(model.snapshot["host"]) + " · " + display(model.snapshot["uptime"])).font(.headline)
                HStack {
                    Metric(title: "CPU", value: number(dictionary(model.snapshot["cpu"])["usage"]))
                    Metric(title: "記憶體", value: number(dictionary(model.snapshot["memory"])["used_percent"]))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(groups.indices, id: \.self) { index in
                            if let data = model.snapshot[groups[index].0] {
                                DisclosureGroup(groups[index].1) { JSONInspector(value: data).padding(8) }
                            }
                        }
                        DisclosureGroup("完整系統資料（包括每核心 CPU、記憶體壓力與硬件資料）") { JSONInspector(value: model.snapshot).padding(8) }
                        Text("欄位由 Mole 與硬件提供；不支援的讀數可能缺省或為 0。程序資料若標示 stale，代表沿用較早快照。").font(.caption).foregroundColor(.secondary)
                    }
                }.frame(minHeight: 210)
            }
        }
    }
}

struct DiskView: View {
    @ObservedObject var model: AppModel
    @State private var quickLookProcess: Process?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { model.analyze(URL(fileURLWithPath: model.folder).deletingLastPathComponent().path) } label: { Image(systemName: "arrow.up") }
                Text(model.folder).lineLimit(1).truncationMode(.middle).help(model.folder)
                Spacer(); Button("選擇…") { model.chooseFolder() }; Button("重新分析") { model.analyze() }
            }.disabled(model.runner.busy)
            HStack {
                TextField("搜尋檔案", text: $model.diskQuery)
                Toggle("大型檔案", isOn: $model.largeOnly)
                Toggle("按名稱", isOn: $model.sortByName)
            }.disabled(model.runner.busy)
            if let report = model.disk {
                Text("\(bytes(report.total_size)) · \(report.total_files ?? 0) 個檔案").font(.headline)
                List(model.diskRows, selection: $model.diskSelection) { entry in
                    HStack {
                        Image(systemName: entry.is_dir == true ? "folder" : "doc")
                        VStack(alignment: .leading) {
                            Text(entry.name).lineLimit(1)
                            ProgressView(value: min(Double(max(0, entry.size)), Double(max(1, report.total_size))), total: Double(max(1, report.total_size)))
                        }
                        Text(bytes(entry.size)).monospacedDigit().frame(width: 100, alignment: .trailing)
                        if entry.is_dir == true { Button("開啟") { model.analyze(entry.path) } }
                        Button("查看") { quickLook(entry.path) }
                        Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
                    }.padding(.vertical, 3).tag(entry.path)
                }.frame(minHeight: 260).disabled(model.runner.busy)
                HStack {
                    Text("按 ⌘ 可多選").font(.caption).foregroundColor(.secondary)
                    Spacer(); Button("移到垃圾桶", action: model.trashFiles).disabled(model.runner.busy || model.diskSelection.isEmpty)
                }
            } else { Text("分析資料夾或外置磁碟，查看容量分布及大型檔案。").foregroundColor(.secondary) }
        }
    }
    private func quickLook(_ path: String) {
        quickLookProcess?.terminate()
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage"); process.arguments = ["-p", path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); quickLookProcess = process } catch { model.notice = error.localizedDescription }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Button("載入操作紀錄", action: model.loadHistory).disabled(model.runner.busy); TextField("搜尋紀錄", text: $query) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("最近操作").font(.headline)
                    records(model.history["sessions"], titleKey: "command", dateKey: "started_at")
                    Divider(); Text("檔案紀錄").font(.headline)
                    records(model.history["deletions"], titleKey: "path", dateKey: "timestamp")
                }
            }.frame(minHeight: 280)
        }
    }
    private func records(_ value: Any?, titleKey: String, dateKey: String) -> some View {
        let rows = (value as? [[String: Any]] ?? []).filter { query.isEmpty || String(describing: $0).localizedCaseInsensitiveContains(query) }
        return VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty { Text("沒有符合的紀錄").foregroundColor(.secondary) }
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(display(row[titleKey])).font(.headline).textSelection(.enabled)
                        Text(display(row[dateKey]) + " · " + display(row["status"] ?? row["size"])).font(.caption).foregroundColor(.secondary)
                        DisclosureGroup("操作詳情") { JSONInspector(value: row) }
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
