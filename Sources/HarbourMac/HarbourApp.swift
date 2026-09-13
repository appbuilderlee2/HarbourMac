import SwiftUI
import AppKit
import Combine
import HarbourCore

enum Page: String, CaseIterable, Identifiable {
    case status = "系統監察", disk = "磁碟瀏覽", clean = "清理", uninstall = "移除 App", optimize = "系統維護", purge = "開發檔案", installer = "安裝檔", external = "外置磁碟", history = "操作紀錄", protection = "保護及路徑", settings = "設定及更新"
    var id: String { rawValue }
    var command: String {
        switch self { case .clean: return "clean"; case .uninstall: return "uninstall"; case .optimize: return "optimize"; case .purge: return "purge"; case .installer: return "installer"; case .external: return "external"; default: return "" }
    }
    var icon: String {
        switch self { case .status: return "waveform.path.ecg"; case .disk: return "internaldrive"; case .clean: return "sparkles"; case .uninstall: return "app.badge"; case .optimize: return "wrench.and.screwdriver"; case .purge: return "chevron.left.forwardslash.chevron.right"; case .installer: return "shippingbox"; case .external: return "externaldrive"; case .history: return "clock"; case .protection: return "checkmark.shield"; case .settings: return "gearshape" }
    }
    var subtitle: String {
        switch self {
        case .clean: return "快取、日誌、暫存及殘留資料。先預覽，再按目前狀態執行清理。"
        case .uninstall: return "掃描 App → 勾選 → 核對相關檔案 → 最終確認。Homebrew App 的設定可能永久刪除。"
        case .optimize: return "檢查及整理 Finder、DNS、資料庫與系統服務。"
        case .purge: return "按專案選擇可重建的開發檔案；最近使用與雲端項目預設不勾選。"
        case .installer: return "掃描 DMG、PKG、ISO、XIP 及安裝 ZIP，永久刪除你選擇的檔案。"
        case .external: return "只清理所選外置磁碟上 Mole 支援的暫存與中繼資料。"
        default: return ""
        }
    }
}
struct Candidate: Identifiable {
    let id: Int
    let name: String
    let path: String
    let detail: String
}
struct DiskEntry: Decodable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let size: Int64
    let is_dir: Bool?
}
struct DiskReport: Decodable {
    let path: String
    let entries: [DiskEntry]?
    let large_files: [DiskEntry]?
    let total_size: Int64
    let total_files: Int?
}

@MainActor final class AppModel: ObservableObject {
    let runner = Runner()
    private var cancellable: AnyCancellable?
    @Published var page: Page? = .status
    @Published var rows: [Candidate] = []
    @Published var selected: Set<Int> = []
    @Published var selecting = false
    @Published var selectionTitle = ""
    @Published var selectionNote = ""
    @Published var confirm: String?
    @Published var query = ""
    @Published var notice = ""
    @Published var snapshot: [String: Any] = [:]
    @Published var history: [String: Any] = [:]
    @Published var disk: DiskReport?
    @Published var folder = FileManager.default.homeDirectoryForCurrentUser.path
    @Published var diskQuery = ""
    @Published var largeOnly = false
    @Published var sortByName = false
    @Published var diskSelection: Set<String> = []
    @Published var externalPath = ""
    @Published var admin = false
    @Published var configKind = "clean"
    @Published var configText = ""
    @Published var configLoaded = false
    @Published var cliPath = UserDefaults.standard.string(forKey: "molePath") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/mo").path
    @Published var watch = false
    @Published var versionInfo = "內置引擎：Mole 1.53.0（固定版本）"
    @Published var busyNetwork = false
    private var previews: [String: Date] = [:]

    init() {
        cancellable = runner.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        runner.onEvent = { [weak self] event in self?.handle(event) }
    }
    var previewKey: String { (page?.command ?? "") + "|" + externalPath + "|" + String(admin) }
    var canApply: Bool {
        if let page = page, [Page.uninstall, .purge, .installer].contains(page) { return true }
        guard let stamp = previews[previewKey] else { return false }
        return Date().timeIntervalSince(stamp) < 600
    }
    var visibleRows: [Candidate] { rows.filter { query.isEmpty || ($0.name + $0.path + $0.detail).localizedCaseInsensitiveContains(query) } }
    func resetSession() {
        rows = []; selected = []; selecting = false; confirm = nil; query = ""; notice = ""; runner.onLine = nil
    }
    func handle(_ event: BridgeEvent) {
        switch event.kind {
        case "begin": rows = []; selected = []; selectionTitle = event.fields[0]; selectionNote = event.fields[1]
        case "row":
            guard let id = Int(event.fields[0]), id >= 0, !rows.contains(where: { $0.id == id }) else { runner.stop(); return }
            rows.append(Candidate(id: id, name: event.fields[1], path: event.fields[2], detail: event.fields[3]))
            if event.fields[4] == "true" { selected.insert(id) }
        case "select": selecting = true
        case "confirm": selecting = false; confirm = event.fields[0]
        case "config": configText = event.fields[0]; configLoaded = true
        default: break
        }
    }
    func submitSelection() {
        guard let response = TextFormat.selection(selected, available: Set(rows.map(\.id))) else { return }
        selecting = false; runner.send(response)
    }
    func confirmAction(_ yes: Bool) {
        confirm = nil; runner.send(yes ? "CONFIRM\n" : "CANCEL\n")
        if !yes { notice = "你已取消此操作。" }
    }
    func cancel() { selecting = false; confirm = nil; watch = false; runner.stop() }
    func bridge(_ command: String, apply: Bool, args: [String] = [], completion: ((Data, Int32) -> Void)? = nil) {
        guard !runner.busy else { return }
        resetSession()
        runner.start(URL(fileURLWithPath: "/bin/bash"), [runner.resourceURL.appendingPathComponent("bridge.sh").path, command, apply ? "apply" : "preview"] + args, environment: ["HARBOUR_ADMIN": admin ? "1" : "0"]) { [weak self] data, rc in
            self?.selecting = false; self?.confirm = nil
            completion?(data, rc)
        }
    }
    func operate(_ apply: Bool) {
        guard let page = page, !page.command.isEmpty, !runner.busy else { return }
        guard !apply || canApply else { notice = "請先完成預覽；預覽有效期為 10 分鐘。"; return }
        if page == .external && externalPath.isEmpty { notice = "請先選擇外置磁碟。"; return }
        let key = previewKey
        previews[key] = nil
        bridge(page.command, apply: apply, args: page == .external ? [externalPath] : []) { [weak self] _, rc in
            if !apply && rc == 0 { self?.previews[key] = Date() }
        }
    }
    func chooseFolder(external: Bool = false) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if external { panel.directoryURL = URL(fileURLWithPath: "/Volumes") }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if external { externalPath = url.path } else { folder = url.path; analyze() }
    }
    func analyze(_ path: String? = nil) {
        guard !runner.busy else { return }
        if let path = path { folder = path }
        resetSession(); disk = nil; diskSelection = []
        runner.start(runner.engineURL.appendingPathComponent("bin/analyze-go"), ["--json", folder], timeout: 1800) { [weak self] data, rc in
            guard rc == 0 else { return }
            do { self?.disk = try JSONDecoder().decode(DiskReport.self, from: data) }
            catch { self?.notice = "磁碟報告格式錯誤：\(error.localizedDescription)" }
        }
    }
    var diskRows: [DiskEntry] {
        let list = largeOnly ? (disk?.large_files ?? []) : (disk?.entries ?? [])
        return list.filter { diskQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(diskQuery) }
            .sorted { sortByName ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.size > $1.size }
    }
    func trashFiles() {
        let allowed = Set(diskRows.map(\.path))
        guard !diskSelection.isEmpty, diskSelection.isSubset(of: allowed) else { return }
        bridge("trash", apply: true, args: diskSelection.sorted()) { [weak self] _, _ in
            self?.disk = nil; self?.diskSelection = []; self?.notice = "磁碟內容可能已改變，請重新分析。"
        }
    }
    func loadStatus(live: Bool) {
        guard !runner.busy else { return }
        resetSession(); watch = live
        if live {
            runner.onLine = { [weak self] line in
                guard let data = line.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                self?.snapshot = value
            }
        }
        runner.start(runner.engineURL.appendingPathComponent("bin/status-go"), live ? ["--watch", "--interval", "2s"] : ["--json"], timeout: live ? 0 : 120) { [weak self] data, rc in
            guard let self = self else { return }
            self.watch = false; self.runner.onLine = nil
            guard !live, rc == 0 else { return }
            if let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.snapshot = value }
            else { self.notice = "未能解析系統狀態。" }
        }
    }
    func loadHistory() {
        guard !runner.busy else { return }; resetSession()
        runner.start(URL(fileURLWithPath: "/bin/bash"), [runner.engineURL.appendingPathComponent("mole").path, "history", "--json"]) { [weak self] data, rc in
            guard rc == 0, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            self?.history = value
        }
    }
    func loadConfig() {
        configLoaded = false
        bridge(configKind == "purgepaths" ? "purgepaths" : "whitelist", apply: false, args: configKind == "purgepaths" ? [] : [configKind])
    }
    func saveConfig() {
        guard configLoaded else { return }
        let lines = configText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let prefix = configKind == "purgepaths" ? [] : [configKind]
        bridge(configKind == "purgepaths" ? "purgepaths" : "whitelist", apply: true, args: prefix + lines) { [weak self] _, rc in
            if rc == 0 { self?.previews = [:]; self?.notice = "已儲存；之前的清理預覽已失效。" }
        }
    }
    func addConfigPath() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = configKind != "purgepaths"
        if panel.runModal() == .OK, let url = panel.url { configText += (configText.hasSuffix("\n") || configText.isEmpty ? "" : "\n") + url.path + "\n" }
    }
    func chooseCLI() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { cliPath = url.path; UserDefaults.standard.set(cliPath, forKey: "molePath") }
    }
    func cliVersion() {
        guard !runner.busy else { return }; resetSession()
        runner.start(URL(fileURLWithPath: cliPath), ["--version"])
    }
    func updateCLI() {
        let alert = NSAlert(); alert.messageText = "更新外部 Mole CLI？"
        alert.informativeText = "更新 \(cliPath)。Harbour 的內置相容引擎保持 1.53.0；需要新版 Harbour 才會更新。"
        alert.addButton(withTitle: "更新"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        resetSession(); runner.start(URL(fileURLWithPath: cliPath), ["update"])
    }
    func checkLatest() {
        guard !busyNetwork else { return }; busyNetwork = true
        let url = URL(string: "https://api.github.com/repos/tw93/Mole/releases/latest")!
        var request = URLRequest(url: url); request.setValue("HarbourMac", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                self?.busyNetwork = false
                if code == 200, let tag = object?["tag_name"] as? String { self?.versionInfo = "內置：1.53.0 · 官方最新穩定版：\(tag)" }
                else { self?.versionInfo = "未能檢查更新：\(error?.localizedDescription ?? "HTTP \(code ?? 0)")" }
            }
        }.resume()
    }
    func exportLog() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Harbour-result.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do { try runner.log.write(to: url, atomically: true, encoding: .utf8) }
            catch { notice = error.localizedDescription }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @State private var logExpanded = true
    var body: some View {
        NavigationView {
            List(Page.allCases, selection: $model.page) { page in Label(page.rawValue, systemImage: page.icon).tag(page) }
                .listStyle(SidebarListStyle()).frame(minWidth: 175, idealWidth: 190).disabled(model.runner.busy)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text(model.page?.rawValue ?? "Harbour").font(.largeTitle.bold()); Text("Harbour 0.3.0").font(.caption).foregroundColor(.secondary) }
                    Spacer()
                    if model.runner.busy { ProgressView().controlSize(.small); Button("停止", action: model.cancel) }
                }
                if !(model.page?.command.isEmpty ?? true) { operationView }
                else {
                    switch model.page {
                    case .status: DashboardView(model: model)
                    case .disk: DiskView(model: model)
                    case .history: HistoryView(model: model)
                    case .protection: protectionView
                    case .settings: settingsView
                    default: EmptyView()
                    }
                }
                if model.selecting { selectionView }
                if let prompt = model.confirm {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(prompt, systemImage: "exclamationmark.triangle").font(.headline)
                            Text("請核對下方本次掃描結果。確認後會執行；取消或關閉 App 不會自動確認。")
                            HStack { Button("取消") { model.confirmAction(false) }; Spacer(); Button("確認繼續") { model.confirmAction(true) }.keyboardShortcut(.defaultAction) }
                        }.padding(6)
                    }
                }
                if !model.notice.isEmpty { Text(model.notice).foregroundColor(.orange).textSelection(.enabled) }
                HStack { Text(model.runner.outcome).font(.caption).foregroundColor(.secondary); Spacer(); Button("匯出結果", action: model.exportLog).disabled(model.runner.log.isEmpty) }
                DisclosureGroup("本次詳細結果", isExpanded: $logExpanded) {
                    ScrollView { Text(model.runner.log.isEmpty ? "等待操作" : model.runner.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(minHeight: 70, maxHeight: model.confirm == nil ? 180 : 280)
                }
            }.padding(24).frame(minWidth: 640, minHeight: 630)
        }.frame(minWidth: 860, minHeight: 690)
        .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
        .onChange(of: model.confirm) { value in if value != nil { logExpanded = true } }
        .onChange(of: model.configKind) { _ in model.configLoaded = false; model.configText = "" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cancel() }
    }
    private var operationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.page?.subtitle ?? "").foregroundColor(.secondary)
            if model.page == .clean { Toggle("包括需要管理員權限的系統項目", isOn: $model.admin).disabled(model.runner.busy) }
            if model.page == .external {
                HStack { Text(model.externalPath.isEmpty ? "未選擇磁碟" : model.externalPath).lineLimit(1); Button("選擇磁碟…") { model.chooseFolder(external: true) }.disabled(model.runner.busy) }
            }
            HStack {
                Button("預覽（不刪除）") { model.operate(false) }.disabled(model.runner.busy)
                Button((model.page.map { [Page.uninstall, .purge, .installer].contains($0) } ?? false) ? "掃描並選擇清理項目" : "執行") { model.operate(true) }.disabled(model.runner.busy || !model.canApply)
            }
        }
    }
    private var selectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.selectionTitle).font(.headline)
            Text(model.selectionNote).font(.caption).foregroundColor(.secondary)
            HStack {
                TextField("搜尋名稱或路徑", text: $model.query)
                Button("全選搜尋結果") { model.selected.formUnion(model.visibleRows.map(\.id)) }
                Button("取消全選") { model.selected = [] }
            }
            List(model.visibleRows) { row in
                Toggle(isOn: Binding(get: { model.selected.contains(row.id) }, set: { yes in if yes { model.selected.insert(row.id) } else { model.selected.remove(row.id) } })) {
                    VStack(alignment: .leading, spacing: 2) { Text(row.name); Text(row.detail).font(.caption).foregroundColor(.secondary); Text(row.path).font(.caption2).foregroundColor(.secondary).lineLimit(1).help(row.path) }
                }.toggleStyle(CheckboxToggleStyle())
            }.frame(minHeight: 170, maxHeight: 300)
            HStack { Text("已選 \(model.selected.count)／\(model.rows.count) 項"); Spacer(); Button("繼續核對", action: model.submitSelection).disabled(model.selected.isEmpty) }
        }
    }
    private var protectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("清單", selection: $model.configKind) { Text("清理白名單").tag("clean"); Text("維護白名單").tag("optimize"); Text("專案掃描路徑").tag("purgepaths") }.pickerStyle(SegmentedPickerStyle()).disabled(model.runner.busy)
            Text("一行一個路徑、模式或維護 task ID。白名單代表保留／略過；# 開頭為註解。先載入現有清單再修改。").foregroundColor(.secondary)
            HStack { Button("載入", action: model.loadConfig); Button("加入路徑…", action: model.addConfigPath).disabled(!model.configLoaded); Spacer(); Button("儲存", action: model.saveConfig).disabled(!model.configLoaded) }.disabled(model.runner.busy)
            TextEditor(text: $model.configText).font(.system(.body, design: .monospaced)).frame(minHeight: 240).disabled(!model.configLoaded || model.runner.busy)
            Link("Mole 白名單與維護說明", destination: URL(string: "https://github.com/tw93/Mole#quick-start")!)
        }
    }
    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("外觀", selection: $appearance) { Text("跟隨系統").tag("system"); Text("淺色").tag("light"); Text("深色").tag("dark") }
                GroupBox("引擎與版本") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.versionInfo)
                        Text("GUI 內置相容引擎，可直接使用。外部 mo 指令可獨立安裝或更新。").foregroundColor(.secondary)
                        HStack { Button("檢查官方版本", action: model.checkLatest).disabled(model.busyNetwork); Link("官方發布紀錄", destination: URL(string: "https://github.com/tw93/Mole/releases")!) }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("外部 Mole CLI") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.cliPath).font(.caption).textSelection(.enabled)
                        HStack { Button("選擇 mo…", action: model.chooseCLI); Button("偵測版本", action: model.cliVersion); Button("安裝 CLI") { model.bridge("install", apply: true) }; Button("更新 CLI", action: model.updateCLI) }
                        HStack { Button("預覽移除 Mole") { model.bridge("remove", apply: false) }; Button("移除 Mole CLI／設定") { model.bridge("remove", apply: true) } }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Touch ID 與命令補完") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("2016 年 12 吋 MacBook 沒有 Touch ID；配備 Touch Bar 的 MacBook Pro 才有相關硬件。")
                        HStack { Button("Touch ID 狀態") { model.bridge("touchid", apply: false, args: ["status"]) }; Button("啟用") { model.bridge("touchid", apply: true, args: ["enable"]) }; Button("停用") { model.bridge("touchid", apply: true, args: ["disable"]) } }
                        HStack { Text("產生補完腳本："); ForEach(["zsh", "bash", "fish"], id: \.self) { shell in Button(shell) { model.bridge("completion", apply: false, args: [shell]) } } }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Harbour 0.3.0 · Intel / macOS 12+\nMole © tw93 與貢獻者 · GPL-3.0\n本 App 為獨立開源 GUI，並非官方 Mole for Mac。").font(.caption).foregroundColor(.secondary)
            }.disabled(model.runner.busy)
        }.frame(minHeight: 360)
    }
}

final class HarbourDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct HarbourApp: App {
    @NSApplicationDelegateAdaptor(HarbourDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene { WindowGroup("Harbour") { ContentView(model: model) } }
}
