import SwiftUI
import AppKit
import Combine
import HarbourCore

enum Page: String, CaseIterable, Identifiable {
    case updates = "軟體更新", login = "登入項目", accessories = "配件電量", fans = "風扇狀態"
    case status = "系統監察", disk = "磁碟瀏覽", clean = "清理", uninstall = "移除 App", optimize = "系統維護", purge = "開發檔案", installer = "安裝檔", external = "外置磁碟", history = "操作紀錄", protection = "保護及路徑", settings = "設定及更新"
    var id: String { rawValue }
    var command: String {
        switch self { case .clean: return "clean"; case .uninstall: return "uninstall"; case .optimize: return "optimize"; case .purge: return "purge"; case .installer: return "installer"; case .external: return "external"; default: return "" }
    }
    var icon: String {
        switch self { case .updates: return "arrow.down.circle"; case .login: return "power"; case .accessories: return "battery.100"; case .fans: return "wind"; case .status: return "waveform.path.ecg"; case .disk: return "internaldrive"; case .clean: return "sparkles"; case .uninstall: return "app.badge"; case .optimize: return "wrench.and.screwdriver"; case .purge: return "chevron.left.forwardslash.chevron.right"; case .installer: return "shippingbox"; case .external: return "externaldrive"; case .history: return "clock"; case .protection: return "checkmark.shield"; case .settings: return "gearshape" }
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
    let hud = HUDController()
    private var mainWindow: NSWindow?

    func captureMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.isReleasedWhenClosed = false
        hud.openWindow = { [weak self] in self?.reopenMainWindow() }
        hud.openSettings = { [weak self] in self?.reopenMainWindow(settings: true) }
    }
    func reopenMainWindow(settings: Bool = false) {
        // Never change the operation page while a confirmation or task is active.
        if settings && !runner.busy { page = .settings }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private var cancellable: AnyCancellable?
    @Published private(set) var page: Page? = .status
    private var lastPages: [ObservatorySection: Page] = [:]
    var canNavigate: Bool { !runner.busy && !selecting && confirm == nil }

    func navigate(to destination: Page) {
        guard canNavigate else { return }
        if let section = ObservatorySection.containing(destination) {
            lastPages[section] = destination
        }
        page = destination
    }

    func navigate(to section: ObservatorySection) {
        guard let destination = lastPages[section] ?? section.pages.first else { return }
        navigate(to: destination)
    }
    @Published var rows: [Candidate] = []
    @Published var selected: Set<Int> = []
    @Published var selecting = false
    @Published var selectionTitle = ""
    @Published var selectionNote = ""
    @Published var selectionSubmitted = false
    @Published var confirm: String?
    @Published var query = ""
    @Published var notice = ""
    @Published var snapshot: [String: Any] = [:]
    @Published private(set) var statusHistory = StatusHistory()
    @Published private(set) var statusReadFailed = false
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
    @Published private(set) var cleanPreview = CleanPreviewSession()
    @Published private(set) var cleanPreviewStarted = false
    private var receivingCleanPreview = false
    private var cleanPreviewKey: String?
    private var cleanPreviewStamp: Date?
    var previewGeneration = UUID()

    func beginCleanPreview() {
        cleanPreview = CleanPreviewSession(); cleanPreviewStarted = true
        receivingCleanPreview = true; cleanPreviewKey = previewKey; cleanPreviewStamp = nil
        previewGeneration = UUID()
    }
    func finishCleanPreview(exitCode: Int32) {
        guard receivingCleanPreview else { return }
        cleanPreview.finish(exitCode: exitCode); receivingCleanPreview = false
        if cleanPreview.isSuccessful {
            cleanPreviewStamp = Date()
            runner.taskPhase = "預覽完成"
        } else {
            cleanPreviewStamp = nil
            notice = "清理預覽不完整或格式無效；請重新掃描。"
            runner.taskPhase = "預覽未完成"
            runner.outcome = "清理預覽未完整完成；請重新掃描"
        }
    }
    func cleanSizeText(_ item: CleanPreviewItem) -> String {
        guard let bytes = item.bytes else { return "未知" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    var cleanTotalText: String {
        let size = ByteCountFormatter.string(fromByteCount: cleanPreview.knownBytes, countStyle: .file)
        if !cleanPreview.isSuccessful { return "已接收 \(cleanPreview.items.count) 項；完整大小尚未確認" }
        return cleanPreview.unknownSizeCount == 0 ? "估計可清理：\(size)" : "已知大小：\(size)；\(cleanPreview.unknownSizeCount) 項大小未知"
    }

    init() {
        cancellable = runner.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        runner.onEvent = { [weak self] event in self?.handle(event) }
        runner.onInvalidPreview = { [weak self] in
            guard let self = self, self.receivingCleanPreview else { return }
            self.cleanPreview.invalidate()
        }
    }
    var previewKey: String { (page?.command ?? "") + "|" + externalPath + "|" + String(admin) }
    var isSelectionOperation: Bool {
        guard let page = page else { return false }
        return [Page.uninstall, .purge, .installer].contains(page)
    }
    var actionTitle: String {
        guard let page = page else { return "操作" }
        switch page {
        case .uninstall: return "掃描已安裝 App"
        case .purge: return "掃描開發檔案"
        case .installer: return "搜尋安裝檔"
        case .clean: return "分析可清理項目"
        case .optimize: return "檢查系統維護項目"
        case .external: return "掃描外置磁碟"
        case .disk: return "分析磁碟"
        case .status: return "讀取系統狀態"
        default: return "執行操作"
        }
    }
    var actionInstructions: String {
        guard let page = page else { return "" }
        switch page {
        case .uninstall: return "先掃描，完成後勾選你確定不要的 App；下一步會先顯示相關檔案，最後才會要求確認。"
        case .purge: return "只會列出可重新產生的開發檔案。近期使用或雲端同步項目預設保留。"
        case .installer: return "找出下載資料夾內的安裝檔。勾選後會永久刪除選取的檔案。"
        case .clean: return "先按「預覽清理」了解會處理什麼。預覽不會刪除資料，但會寫入預覽檔、暫存紀錄，啟用操作日誌時亦會記錄；執行時引擎會重新掃描。"
        case .optimize: return "先檢查系統維護項目，再由你決定是否執行。"
        case .external: return "先選擇外置磁碟，再預覽 Mole 支援的暫存資料。"
        default: return ""
        }
    }
    var progressMessage: String {
        if isSelectionOperation {
            if selecting { return "掃描完成；你可以慢慢勾選，尚未刪除任何內容。" }
            if confirm != nil { return "請先閱讀最後確認；按下確認執行前，不會刪除任何內容。" }
            if selectionSubmitted { return "已送出選擇，正在核對精確路徑及相關檔案。" }
            if runner.elapsedSeconds >= 30 {
                return "掃描仍在進行；首次掃描會逐一核對 App 及相關檔案。未按最後確認前，不會刪除任何內容。"
            }
            return "目前只是在掃描，尚未刪除任何 App 或檔案。"
        }
        if !runner.taskTitle.hasPrefix("執行") && (runner.taskTitle.contains("預覽") || runner.taskTitle.contains("分析") || runner.taskTitle.contains("檢查")) { return "這一步不會刪除檔案；但預覽及分析可能寫入預覽檔、暫存或日誌紀錄。" }
        if let currentPage = page, [.status, .disk, .history].contains(currentPage) { return "這一步只讀取資料，不會修改或刪除檔案。" }
        return "操作進行中；完成前請不要重覆按其他操作。你可以按「停止」取消。"
    }
    var elapsedText: String {
        let seconds = runner.elapsedSeconds
        if seconds < 60 { return "已用 \(seconds) 秒" }
        return String(format: "已用 %d 分 %02d 秒", seconds / 60, seconds % 60)
    }
    var resultGuide: String {
        if runner.outcome.contains("取消") || runner.outcome.contains("停止") { return "操作已停止；已完成的項目不會自動復原。你可以重新掃描，確認目前狀態。" }
        if runner.outcome.contains("結束") {
            if isSelectionOperation && !selectionSubmitted {
                return "掃描完成。請查看上方清單，勾選需要處理的項目，再按下一步核對。"
            }
            return isSelectionOperation ? "處理完成。你可以重新掃描，確認 App 或檔案目前的狀態。" : "檢查完成。你可以查看詳細結果，或按預覽／執行按鈕進行下一步。"
        }
        if runner.outcome == "尚未執行" { return "" }
        return "操作未完整完成。請展開下方「詳細結果」查看原因，修正後再試。"
    }
    var confirmationTitle: String {
        if isSelectionOperation { return "準備處理你選擇的項目" }
        switch page {
        case .clean: return "準備執行清理"
        case .optimize: return "準備執行系統維護"
        case .external: return "準備清理外置磁碟"
        default: return "最後確認"
        }
    }
    var confirmationMessage: String {
        if isSelectionOperation {
            return "你已選擇 \(selected.count) 項。確認後 Harbour 才會開始處理；你仍可返回修改清單。"
        }
        switch page {
        case .clean: return "確認後引擎會重新掃描，按執行當下狀態清理；範圍不會鎖定在這份清單，部分內容可能永久刪除。"
        case .optimize: return "確認後會執行已檢查的系統維護項目，可能重新整理 Finder、DNS 或系統服務。"
        case .external: return "確認後只會處理你選擇的外置磁碟上的支援項目。"
        default: return "請確認你明白這項操作可能改變本機資料。"
        }
    }
    var canApply: Bool {
        if page == .clean {
            guard cleanPreview.isSuccessful, cleanPreviewKey == previewKey, let stamp = cleanPreviewStamp else { return false }
            return Date().timeIntervalSince(stamp) < 600
        }
        if let page = page, [Page.uninstall, .purge, .installer].contains(page) { return true }
        guard let stamp = previews[previewKey] else { return false }
        return Date().timeIntervalSince(stamp) < 600
    }
    var previewStatus: String? {
        if page == .clean { return canApply ? "預覽已完成；執行時會重新掃描，不會鎖定此清單" : nil }
        guard !isSelectionOperation, let stamp = previews[previewKey] else { return nil }
        let remaining = max(0, 600 - Int(Date().timeIntervalSince(stamp)))
        return remaining > 0 ? "預覽已完成；你可在 \(max(1, remaining / 60)) 分鐘內執行" : nil
    }
    var visibleRows: [Candidate] { rows.filter { query.isEmpty || ($0.name + $0.path + $0.detail).localizedCaseInsensitiveContains(query) } }
    func friendlyDetail(_ detail: String) -> String {
        var value = detail
            .replacingOccurrences(of: "cloud:true", with: "雲端同步")
            .replacingOccurrences(of: "cloud:false", with: "非雲端同步")
            .replacingOccurrences(of: " bytes", with: " bytes")
        if let first = value.components(separatedBy: " · ").first, !first.isEmpty {
            value = "資料大小：\(first)" + (value == first ? "" : " · " + value.components(separatedBy: " · ").dropFirst().joined(separator: " · "))
        }
        return value
    }
    func resetSession() {
        rows = []; selected = []; selecting = false; selectionSubmitted = false; confirm = nil; query = ""; notice = ""; runner.onLine = nil
    }
    func handle(_ event: BridgeEvent) {
        if event.kind.hasPrefix("clean_preview_") {
            guard receivingCleanPreview else { return }
            cleanPreview.consume(event)
            runner.taskPhase = "正在整理清理預覽：\(cleanPreview.items.count) 項"
            return
        }
        switch event.kind {
        case "begin":
            rows = []; selected = []; selectionTitle = event.fields[0]; selectionNote = event.fields[1]
            runner.taskPhase = "正在整理掃描結果…"
        case "row":
            guard let id = Int(event.fields[0]), id >= 0, !rows.contains(where: { $0.id == id }) else { runner.stop(); return }
            rows.append(Candidate(id: id, name: event.fields[1], path: event.fields[2], detail: event.fields[3]))
            if event.fields[4] == "true" { selected.insert(id) }
            runner.taskPhase = "已找到 \(rows.count) 個項目"
        case "select": selecting = true; runner.taskPhase = "請勾選你想處理的項目"
        case "confirm": selecting = false; confirm = event.fields[0]; runner.taskPhase = "等待你最後確認"
        case "config": configText = event.fields[0]; configLoaded = true
        default: break
        }
    }
    func submitSelection() {
        guard let response = TextFormat.selection(selected, available: Set(rows.map(\.id))) else { return }
        selectionSubmitted = true; selecting = false; runner.taskPhase = "正在核對你選擇的項目…"; runner.send(response)
    }
    func confirmAction(_ yes: Bool) {
        confirm = nil; runner.send(yes ? "CONFIRM\n" : "CANCEL\n")
        if yes { runner.taskPhase = "正在執行…" } else { notice = "你已取消此操作。"; runner.taskPhase = "已取消" }
    }
    func cancel() { selecting = false; confirm = nil; watch = false; runner.taskPhase = "正在停止…"; runner.stop() }
    func bridge(_ command: String, apply: Bool, args: [String] = [], title: String? = nil, phase: String? = nil, completion: ((Data, Int32) -> Void)? = nil) {
        guard !runner.busy else { return }
        resetSession()
        receivingCleanPreview = false
        let isCleanPreview = command == "clean" && !apply
        if command == "clean" {
            if isCleanPreview { beginCleanPreview() }
            else { cleanPreviewStamp = nil }
        }
        runner.taskTitle = title ?? (apply && !isSelectionOperation ? "執行\(actionTitle)" : actionTitle)
        runner.taskPhase = phase ?? (apply && !isSelectionOperation ? "正在準備執行…" : "正在掃描，請稍候…")
        runner.start(URL(fileURLWithPath: "/bin/bash"), [runner.resourceURL.appendingPathComponent("bridge.sh").path, command, apply ? "apply" : "preview"] + args, environment: ["HARBOUR_ADMIN": admin ? "1" : "0"]) { [weak self] data, rc in
            self?.selecting = false; self?.confirm = nil
            if rc == 0 { self?.runner.taskPhase = apply ? "完成" : "預覽完成" }
            else if rc == 130 { self?.runner.taskPhase = "已取消" }
            else { self?.runner.taskPhase = "需要查看詳細結果" }
            if isCleanPreview { self?.finishCleanPreview(exitCode: rc) }
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
            if page != .clean && !apply && rc == 0 { self?.previews[key] = Date() }
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
        runner.taskTitle = "分析磁碟"; runner.taskPhase = "正在讀取資料夾及檔案大小…"
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
    // The optional starter is a fixture-only seam; production uses the existing Runner.
    func loadStatus(live: Bool, now: @escaping () -> Date = Date.init,
                    start: ((@escaping (Data, Int32) -> Void) -> Void)? = nil) {
        guard !runner.busy else { return }
        resetSession(); watch = live
        snapshot = [:]; statusHistory = StatusHistory(); statusReadFailed = false
        runner.taskTitle = live ? "持續監察系統" : "讀取系統狀態"; runner.taskPhase = live ? "約每 2 秒採樣；按停止結束監察" : "正在讀取 CPU、記憶體及硬件資料…"
        let ingest: (Data) -> Void = { [weak self] data in
            guard let self = self else { return }
            guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  self.statusHistory.ingest(value, now: now()) else {
                self.statusReadFailed = true
                self.notice = "未能接收有效系統狀態；時間缺漏、過舊、未來、重複或倒序的快照不會更新趨勢。"
                return
            }
            self.snapshot = value; self.statusReadFailed = false; self.notice = ""
        }
        if live {
            runner.onLine = { [weak self] line in
                guard self?.watch == true else { return }
                ingest(Data(line.utf8))
            }
        }
        let completion: (Data, Int32) -> Void = { [weak self] data, rc in
            guard let self = self else { return }
            self.watch = false; self.runner.onLine = nil
            if rc != 0 { self.statusReadFailed = rc != 130; return }
            if !live { ingest(data) }
        }
        if let start = start { start(completion) }
        else {
            runner.start(runner.engineURL.appendingPathComponent("bin/status-go"), live ? ["--watch", "--interval", "2s"] : ["--json"], timeout: live ? 0 : 120, completion: completion)
        }
    }
    func loadHistory() {
        guard !runner.busy else { return }; resetSession()
        runner.taskTitle = "載入操作紀錄"; runner.taskPhase = "正在讀取本機紀錄…"
        runner.start(URL(fileURLWithPath: "/bin/bash"), [runner.engineURL.appendingPathComponent("mole").path, "history", "--json"]) { [weak self] data, rc in
            guard rc == 0, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            self?.history = value
        }
    }
    func loadConfig() {
        configLoaded = false
        bridge(configKind == "purgepaths" ? "purgepaths" : "whitelist", apply: false, args: configKind == "purgepaths" ? [] : [configKind], title: "載入保護設定", phase: "正在讀取本機設定…")
    }
    /// Handles the saveConfig completion: any genuine save attempt invalidates
    /// previews (fail closed on rc!=0 too — a partial write must never leave an
    /// older preview eligible), while the refreshed generation token ensures
    /// late preview callbacks cannot re-stamp an already-expired config view.
    func handleSaveConfigResult(_ rc: Int32) {
        guard configLoaded else { return }
        previews = [:]
        cleanPreview.invalidate()
        cleanPreviewStamp = nil
        notice = rc == 0 ? "已儲存；之前的清理預覽已失效，請重新掃描。"
                         : "儲存未成功確認；之前的清理預覽已失效，請重新掃描。"
        previewGeneration = UUID()
    }
    /// Completion side of saveConfig: results from an older generation (a newer
    /// preview or save has started) are discarded before touching any state.
    func handleSaveCompletion(capturedGeneration: UUID, rc: Int32) {
        guard configLoaded, capturedGeneration == previewGeneration else { return }
        handleSaveConfigResult(rc)
    }
    func saveConfig() {
        guard configLoaded, !runner.busy else { return }
        // The whitelist being written may differ from what any current preview
        // scanned, and a failed write leaves the outcome uncertain: expire
        // preview eligibility the moment the save is attempted (fail closed).
        previews = [:]
        cleanPreview.invalidate()
        cleanPreviewStamp = nil
        previewGeneration = UUID()
        let generation = previewGeneration
        let lines = configText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let prefix = configKind == "purgepaths" ? [] : [configKind]
        bridge(configKind == "purgepaths" ? "purgepaths" : "whitelist", apply: true, args: prefix + lines, title: "儲存保護設定", phase: "正在寫入本機設定…") { [weak self] _, rc in
            self?.handleSaveCompletion(capturedGeneration: generation, rc: rc)
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
        runner.taskTitle = "偵測 Mole CLI 版本"; runner.taskPhase = "正在執行版本檢查…"
        runner.start(URL(fileURLWithPath: cliPath), ["--version"])
    }
    func updateCLI() {
        let alert = NSAlert(); alert.messageText = "更新外部 Mole CLI？"
        alert.informativeText = "更新 \(cliPath)。Harbour 的內置相容引擎保持 1.53.0；需要新版 Harbour 才會更新。"
        alert.addButton(withTitle: "更新"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        resetSession(); runner.taskTitle = "更新 Mole CLI"; runner.taskPhase = "正在下載及安裝更新…"; runner.start(URL(fileURLWithPath: cliPath), ["update"])
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
    @State private var logExpanded = false
    @StateObject private var systemTools = SystemTools()
    var body: some View {
        VStack(spacing: 0) {
            ObservatoryNavigation(model: model)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            PlanetHeader(page: model.page ?? .status)
                            Text(headerSubtitle).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                            Text("Harbour 0.4.1 · Intel / macOS 12+").font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        if model.runner.busy {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Button("停止", action: model.cancel) }
                        }
                    }
                    if model.runner.busy { TaskProgressCard(model: model) }
                    if !(model.page?.command.isEmpty ?? true) { operationView }
                    else {
                        switch model.page {
                        case .status:
                            DashboardView(model: model)
                        case .updates: SoftwareUpdatesView(model: model, tools: systemTools)
                        case .login: LoginItemsView(model: model, tools: systemTools)
                        case .accessories: AccessoriesView(model: model, tools: systemTools)
                        case .fans: FanStatusView(model: model)
                        case .disk: DiskView(model: model)
                        case .history: HistoryView(model: model)
                        case .protection: protectionView
                        case .settings: settingsView
                        default: EmptyView()
                        }
                    }
                    if model.selecting { selectionView }
                    if let prompt = model.confirm { confirmationView(prompt: prompt) }
                    if !model.runner.busy && !model.resultGuide.isEmpty { ResultGuideCard(model: model) }
                    if !model.notice.isEmpty { Text(model.notice).foregroundColor(.orange).textSelection(.enabled) }
                    HStack {
                        Text(model.runner.outcome == "尚未執行" ? "準備就緒" : model.runner.outcome).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button("匯出結果", action: model.exportLog).disabled(model.runner.log.isEmpty)
                    }
                    DisclosureGroup("詳細結果（需要時查看）", isExpanded: $logExpanded) {
                        ScrollView {
                            Text(model.runner.log.isEmpty ? "完成操作後，這裡會顯示詳細記錄。" : model.runner.log)
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(minHeight: 70, maxHeight: model.confirm == nil ? 180 : 280)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minWidth: 640, minHeight: 630)
        }.frame(minWidth: 860, minHeight: 690)
        .background(ObservatoryBackground(page: model.page ?? .clean))
        .preferredColorScheme(appearance == "dark" ? .dark : (appearance == "light" ? .light : nil))
        .onChange(of: model.confirm) { value in if value != nil { logExpanded = true } }
        .onChange(of: model.configKind) { _ in model.configLoaded = false; model.configText = "" }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cancel() }
    }
    private var headerSubtitle: String {
        guard let page = model.page, !page.subtitle.isEmpty else { return "從上方選擇功能；先查看結果，再決定下一步。" }
        return page.subtitle
    }
    private var operationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.page?.icon ?? "wand.and.stars").font(.title2).foregroundColor(.accentColor).frame(width: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("你會做咩？").font(.headline)
                        Text(model.actionInstructions).fixedSize(horizontal: false, vertical: true)
                        Text(model.isSelectionOperation ? "安全提示：掃描期間不會刪除；最後確認前可取消。" : "安全提示：先預覽會顯示將要處理的內容，預覽本身不會刪除資料。")
                            .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(8)
            }
            if model.page == .clean { Toggle("包括需要管理員權限的系統項目", isOn: $model.admin).disabled(model.runner.busy) }
            if model.page == .external {
                HStack { Text(model.externalPath.isEmpty ? "未選擇磁碟" : model.externalPath).lineLimit(1); Button("選擇磁碟…") { model.chooseFolder(external: true) }.disabled(model.runner.busy) }
            }
            HStack {
                if model.isSelectionOperation {
                    Button("開始掃描") { model.operate(true) }.keyboardShortcut(.defaultAction).disabled(model.runner.busy)
                    Text("掃描完成後再選擇項目").font(.caption).foregroundColor(.secondary)
                } else {
                    Button("預覽（不刪除）") { model.operate(false) }.disabled(model.runner.busy)
                    Button(model.page == .clean ? "重新掃描並清理…" : "執行預覽內容") { model.operate(true) }.keyboardShortcut(.defaultAction).disabled(model.runner.busy || !model.canApply)
                    if let status = model.previewStatus { Text(status).font(.caption).foregroundColor(.secondary) }
                }
            }
            if !model.isSelectionOperation && !model.canApply { Text("先完成預覽，執行按鈕才會啟用。").font(.caption).foregroundColor(.secondary) }
            if model.page == .clean && model.cleanPreviewStarted { cleanPreviewView }
        }
    }
    private var cleanPreviewView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.cleanPreview.isSuccessful ? "清理預覽（唯讀）" : "清理預覽（未完整驗證）").font(.headline)
                Text(model.cleanTotalText)
                Text(model.cleanPreview.systemIncluded ? "本次掃描包含系統項目" : "本次掃描不包含系統項目").font(.caption).foregroundColor(.secondary)
                Text("執行時會重新掃描及驗證；這不是已鎖定的刪除清單，亦不提供逐項勾選。").font(.caption).foregroundColor(.secondary)
                if model.cleanPreview.sizingTimeoutCount > 0 {
                    Text("大小檢查逾時：\(model.cleanPreview.sizingTimeoutCount) 次；估算可能不完整。").font(.caption).foregroundColor(.orange)
                }
                if model.cleanPreview.isSuccessful && model.cleanPreview.items.isEmpty { Text("本次掃描沒有可列出的清理項目。") }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.cleanPreview.categories, id: \.self) { category in
                            Text(category).font(.headline)
                            ForEach(model.cleanPreview.items.filter { $0.category == category }) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.path).font(.caption).textSelection(.enabled)
                                    Text("\(model.cleanSizeText(item)) · \(item.itemCount) 項").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 300)
            }.padding(8)
        }
    }
    private var selectionView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("掃描完成", systemImage: "checkmark.circle.fill").font(.headline).foregroundColor(.accentColor)
                    Spacer(); Text("找到 \(model.rows.count) 項").font(.caption).foregroundColor(.secondary)
                }
                Text("請勾選你確定要處理的項目。未勾選的內容會保留；按下一步後還會再顯示一次確認。")
                Text(model.selectionNote).font(.caption).foregroundColor(.secondary)
                Text(model.selectionTitle).font(.caption).foregroundColor(.secondary)
            HStack {
                    TextField("搜尋名稱或路徑", text: $model.query).textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("全選") { model.selected.formUnion(model.visibleRows.map(\.id)) }.disabled(model.visibleRows.isEmpty)
                    Button("清除選擇") { model.selected = [] }.disabled(model.selected.isEmpty)
            }
                if model.visibleRows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.title2).foregroundColor(.secondary)
                        Text(model.rows.isEmpty ? "沒有找到可處理項目" : "沒有符合搜尋的項目").foregroundColor(.secondary)
                        Text(model.rows.isEmpty ? "你可以返回重新掃描，或到「詳細結果」查看原因。" : "清除搜尋文字即可查看全部項目。").font(.caption).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    List(model.visibleRows) { row in
                        Toggle(isOn: Binding(get: { model.selected.contains(row.id) }, set: { yes in if yes { model.selected.insert(row.id) } else { model.selected.remove(row.id) } })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name)
                                Text(model.friendlyDetail(row.detail)).font(.caption).foregroundColor(.secondary)
                                DisclosureGroup("查看檔案位置") {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.path).font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
                                        Text("技術資料：\(row.detail)").font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
                                    }.padding(.top, 2)
                                }
                            }
                        }.toggleStyle(CheckboxToggleStyle())
                    }.frame(minHeight: 170, maxHeight: 300)
                }
                HStack {
                    Text("已選 \(model.selected.count) 項").font(.subheadline)
                    Spacer()
                    Button("下一步：查看會處理的資料", action: model.submitSelection).disabled(model.selected.isEmpty)
                }
            }.padding(8)
        }
    }
    private func confirmationView(prompt: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(model.confirmationTitle, systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundColor(.orange)
                Text(model.confirmationMessage).fixedSize(horizontal: false, vertical: true)
                Text("引擎提示：\(prompt)").font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                HStack {
                    Button("取消並重新掃描") { model.confirmAction(false) }
                    Spacer()
                    Button("確認執行") { model.confirmAction(true) }.keyboardShortcut(.defaultAction)
                }
            }.padding(8)
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
                    HUDSettings(controller: model.hud)
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
                            HStack { Button("選擇 mo…", action: model.chooseCLI); Button("偵測版本", action: model.cliVersion); Button("安裝 CLI") { model.bridge("install", apply: true, title: "安裝 Mole CLI", phase: "正在下載官方 CLI…") }; Button("更新 CLI", action: model.updateCLI) }
                            HStack { Button("預覽移除 Mole") { model.bridge("remove", apply: false, title: "預覽移除 Mole", phase: "正在整理可移除的檔案…") }; Button("移除 Mole CLI／設定") { model.bridge("remove", apply: true, title: "移除 Mole CLI／設定", phase: "正在準備移除…") } }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Touch ID 與命令補完") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("2016 年 12 吋 MacBook 沒有 Touch ID；配備 Touch Bar 的 MacBook Pro 才有相關硬件。")
                            HStack { Button("Touch ID 狀態") { model.bridge("touchid", apply: false, args: ["status"], title: "查看 Touch ID 狀態", phase: "正在檢查硬件支援…") }; Button("啟用") { model.bridge("touchid", apply: true, args: ["enable"], title: "啟用 Touch ID sudo", phase: "正在準備修改設定…") }; Button("停用") { model.bridge("touchid", apply: true, args: ["disable"], title: "停用 Touch ID sudo", phase: "正在準備修改設定…") }
                            }
                            HStack { Text("產生補完腳本："); ForEach(["zsh", "bash", "fish"], id: .self) { shell in Button(shell) { model.bridge("completion", apply: false, args: [shell], title: "產生 \(shell) 補完腳本", phase: "正在產生腳本…") } }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    DoctorView(model: model)
                    Text("Harbour 0.4.1 · Intel / macOS 12+\nMole © tw93 與貢獻者 · GPL-3.0\n本 App 為獨立開源 GUI，並非官方 Mole for Mac.").font(.caption).foregroundColor(.secondary)
                }.disabled(model.runner.busy)
            }.frame(minHeight: 360)
        }
    }
}

struct TaskProgressCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                ProgressView().controlSize(.regular)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(model.runner.taskTitle.isEmpty ? "正在處理" : model.runner.taskTitle).font(.headline)
                        Spacer()
                        Text(model.elapsedText).font(.caption).foregroundColor(.secondary).monospacedDigit()
                    }
                    Text(model.runner.taskPhase.isEmpty ? "正在準備…" : model.runner.taskPhase)
                    Text(model.progressMessage).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(8)
        }
    }
}

struct ResultGuideCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let warning = model.runner.outcome.contains("未完整") || model.runner.outcome.contains("取消") || model.runner.outcome.contains("停止")
        return GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(warning ? .orange : .green).font(.title2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(warning ? "需要留意" : "下一步").font(.headline)
                    Text(model.resultGuide).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(8)
        }
    }
}

@MainActor final class HarbourDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(model?.hud.enabled ?? false)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model?.reopenMainWindow() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.hud.shutdown()
        model?.cancel()
    }
}
@main struct HarbourApp: App {
    @NSApplicationDelegateAdaptor(HarbourDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Harbour") {
            ContentView(model: model)
                .background(MainWindowCapture { window in
                    model.captureMainWindow(window)
                    delegate.model = model
                }.frame(width: 0, height: 0))
        }
    }
}
