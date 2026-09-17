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
                Button(model.watch ? "停止監察" : "持續監察（約每 2 秒）") { if model.watch { model.cancel() } else { model.loadStatus(live: true) } }.disabled(model.runner.busy && !model.watch)
            }
            StatusTrendsView(model: model)
            if model.snapshot.isEmpty { Text("按更新快照取得真實系統資料。").foregroundColor(.secondary) }
            else {
                Text(display(model.snapshot["host"]) + " · " + display(model.snapshot["uptime"])).font(.headline)
                Text("以下資料只作查看，不會修改或清理你的 Mac。CPU、記憶體及電池讀數會因使用情況變動。")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
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
                GroupBox("分析結果") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(bytes(report.total_size)) · \(report.total_files ?? 0) 個檔案").font(.headline)
                        Text("列表按大小排序；分析本身不會刪除資料。先查看最大項目，再決定是否移到垃圾桶。")
                            .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
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
            } else {
                GroupBox("未開始分析") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("按「重新分析」即可查看這個資料夾佔用的空間。")
                        Text("分析只會讀取檔案大小，不會刪除或移動任何內容。")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private func quickLook(_ path: String) {
        quickLookProcess?.terminate()
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage"); process.arguments = ["-p", path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); quickLookProcess = process } catch { model.notice = error.localizedDescription }
    }
}

import HarbourCore

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Button("載入操作紀錄", action: model.loadHistory).disabled(model.runner.busy); TextField("搜尋紀錄", text: $query) }
            if model.history.isEmpty {
                Text("尚未載入紀錄。載入只會讀取本機日誌。").foregroundColor(.secondary)
            } else {
                summaryStrip(HistorySummary(model.history))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("最近操作").font(.headline)
                    records(model.history["sessions"], isSession: true)
                    Divider(); Text("檔案紀錄").font(.headline)
                    records(model.history["deletions"], isSession: false)
                }
            }.frame(minHeight: 280)
        }
    }

    private func summaryStrip(_ summary: HistorySummary) -> some View {
        GroupBox("目前載入紀錄") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading) {
                        Text("操作時段：\(summary.sessions.count)").font(.headline)
                        Text("清理 \(summary.cleanSessionCount) · 系統維護 \(summary.optimizeSessionCount)")
                    }
                    VStack(alignment: .leading) {
                        Text("檔案稽核：\(summary.deletions.count)").font(.headline)
                        Text("永久刪除回報 ok：\(summary.count(.permanentOK)) · 移到垃圾桶回報 ok：\(summary.count(.trashOK))")
                        Text("預覽 \(summary.count(.preview)) · 略過／拒絕 \(summary.count(.skipped)) · 失敗／中斷 \(summary.count(.failed)) · 未知 \(summary.count(.unknown))")
                    }
                }.font(.caption)
                Text("永久刪除 ok 紀錄的已知大小加總：\(summary.knownPermanentBytes.map { bytes($0) } ?? "超出可計算範圍")；大小未知 \(summary.unknownPermanentSizeCount) 筆。")
                    .font(.caption)
                Text("大小為操作前量度，不代表實際釋放空間；紀錄可能重疊。未加上時段大小、垃圾桶、預覽或失敗紀錄。")
                    .font(.caption).foregroundColor(.secondary)
                Text("摘要不隨搜尋改變。只涵蓋目前載入、仍保留的日誌；舊日誌可能已輪替，並非完整歷史。日期依原始紀錄顯示；操作時段沒有時區。")
                    .font(.caption).foregroundColor(.secondary)
                Text("零筆不代表你從未操作，只代表目前沒有載入可辨識的紀錄；日誌也可能不存在。")
                    .font(.caption).foregroundColor(.secondary)
                if let limit = summary.limit {
                    Text("引擎每類最多載入 \(limit) 筆。" + (summary.sessionLimitReached || summary.deletionLimitReached ? "已達載入上限，可能還有較舊紀錄。" : "未達上限亦不代表日誌完整。"))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("未提供有效載入上限，無法判斷是否截斷。").font(.caption).foregroundColor(.secondary)
                }
                if summary.hasInvalidCollections || summary.invalidRowCount > 0 {
                    Text("部分紀錄缺漏或格式無效；摘要只計算可辨識的紀錄。").font(.caption).foregroundColor(.orange)
                }
                Text("前往功能只會切換頁面，不會重播紀錄或開始清理；請重新查看目前狀態。")
                    .font(.caption).foregroundColor(.secondary)
            }.fixedSize(horizontal: false, vertical: true).padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func records(_ value: Any?, isSession: Bool) -> some View {
        let rows = (value as? [Any] ?? []).compactMap { $0 as? [String: Any] }
            .filter { query.isEmpty || String(describing: $0).localizedCaseInsensitiveContains(query) }
        return VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty { Text("沒有符合的紀錄").foregroundColor(.secondary) }
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        if isSession {
                            sessionHeader(HistorySession(row))
                        } else {
                            Text(display(row["path"])).font(.headline).textSelection(.enabled)
                            Text(display(row["timestamp"]) + " · " + display(row["status"])).font(.caption).foregroundColor(.secondary)
                        }
                        DisclosureGroup("操作詳情") { JSONInspector(value: row) }
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func sessionHeader(_ session: HistorySession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.command ?? "未提供指令").font(.headline).textSelection(.enabled)
            Text((session.startedAt ?? "未提供開始時間") + " · 結束：" + (session.endedAt ?? "未記錄（不代表仍在執行）"))
                .font(.caption).foregroundColor(.secondary)
            Text("移除 \(countText(session.actions.removed)) · 垃圾桶 \(countText(session.actions.trashed)) · 略過 \(countText(session.actions.skipped)) · 失敗 \(countText(session.actions.failed)) · 維護任務失敗 \(countText(session.failedTasks))")
                .font(.caption).foregroundColor(.secondary)
            Text("時段回報大小：\(session.reportedSize ?? "未知")（不加入檔案大小加總）")
                .font(.caption).foregroundColor(.secondary)
            if session.command == "clean" {
                Button("前往清理") { model.navigate(to: Page.clean) }.disabled(!model.canNavigate)
            } else if session.command == "optimize" {
                Button("前往系統維護") { model.navigate(to: Page.optimize) }.disabled(!model.canNavigate)
            }
        }
    }

    private func countText(_ value: Int64?) -> String { value.map { String($0) } ?? "未知" }
}
