import SwiftUI
import AppKit
import Combine
import HarbourCore

struct InstalledSoftware: Identifiable {
    var id: String { url.path }
    let url: URL
    let name: String
    let version: String
    let source: String
    let feed: URL?
}
struct LoginEntry: Identifiable, Decodable {
    var id: String { path + name }
    let name: String
    let path: String
    let hidden: Bool
}
struct AgentEntry: Identifiable {
    var id: String { url.path }
    let url: URL
    let label: String
    let scope: String
}

@MainActor final class SystemTools: ObservableObject {
    @Published var software: [InstalledSoftware] = []
    @Published var packages: [PackageUpdate] = []
    @Published var feedResults: [String: String] = [:]
    @Published var loginItems: [LoginEntry] = []
    @Published var agents: [AgentEntry] = []
    @Published var accessories: [AccessoryReading] = []
    @Published var softwareNote = "尚未掃描"
    @Published var brewNote = "尚未檢查"
    @Published var storeNote = "尚未檢查"
    @Published var loginNote = "尚未讀取"
    @Published var accessoryNote = "尚未讀取"
    @Published var pendingPackage: PackageUpdate?
    @Published var scanning = false
    private var inventoryGeneration = UUID()
    var brewURL: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }.map { URL(fileURLWithPath: $0) }
    }
    private func run(_ model: AppModel, executable: URL, arguments: [String], title: String,
                     timeout: TimeInterval = 120, completion: @escaping (Data, Int32) -> Void) {
        guard !model.runner.busy else { return }
        model.runner.onLine = nil
        model.runner.taskTitle = title
        model.runner.start(executable, arguments, environment: [
            "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1",
            "HOMEBREW_NO_INSTALL_CLEANUP": "1"
        ], timeout: timeout, completion: completion)
    }
    func scanSoftware() {
        guard !scanning else { return }
        scanning = true; softwareNote = "正在讀取已安裝 App…"
        let generation = UUID(); inventoryGeneration = generation
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let roots = [URL(fileURLWithPath: "/Applications"),
                         fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            var rows: [InstalledSoftware] = []
            var unreadable: [String] = []
            for root in roots {
                guard fm.fileExists(atPath: root.path) else { continue }
                guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                 errorHandler: { url, _ in unreadable.append(url.lastPathComponent); return true }) else {
                    unreadable.append(root.path); continue
                }
                for case let url as URL in walker where url.pathExtension.lowercased() == "app" {
                    guard let bundle = Bundle(url: url), let info = bundle.infoDictionary else { continue }
                    let receipt = fm.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
                    let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
                    rows.append(InstalledSoftware(url: url,
                        name: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent,
                        version: info["CFBundleShortVersionString"] as? String ?? "未提供",
                        source: receipt ? "App Store" : (feed == nil ? "App 自行更新" : "Sparkle"),
                        feed: receipt ? nil : feed))
                }
            }
            let result = rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let note = "找到 \(result.count) 個 App。" + (unreadable.isEmpty ? "" : " 部分位置無法讀取，結果不完整。")
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.inventoryGeneration == generation else { return }
                self.software = result; self.softwareNote = note; self.scanning = false
                self.feedResults = [:]
            }
        }
    }
    func checkBrew(_ model: AppModel, refresh: Bool = false) {
        guard let brew = brewURL else { brewNote = "未安裝 Homebrew；其他更新來源仍可使用。"; return }
        packages = []; brewNote = refresh ? "正在更新 Homebrew 軟體目錄…" : "正在檢查本機 Homebrew 目錄…"
        if refresh {
            run(model, executable: brew, arguments: ["update"], title: "更新 Homebrew 軟體目錄", timeout: 300) { [weak self] _, rc in
                guard let self = self else { return }
                guard rc == 0 else { self.brewNote = "目錄更新失敗或已取消，請查看詳細結果。"; return }
                self.checkBrew(model)
            }
            return
        }
        run(model, executable: brew, arguments: ["outdated", "--json=v2"], title: "檢查 Homebrew 更新") { [weak self] data, rc in
            guard let self = self else { return }
            guard rc == 0 else { self.brewNote = "檢查失敗或已取消；不能判定是否最新。"; return }
            do {
                self.packages = try SystemData.brewUpdates(data)
                self.brewNote = "本機目錄結果：\(self.packages.count) 項可更新。最新目錄請按「更新目錄並檢查」。自動更新 App 及 latest cask 可能略過。"
            } catch { self.brewNote = "Homebrew 回應格式無法辨識。"; }
        }
    }
    func upgrade(_ package: PackageUpdate, model: AppModel) {
        pendingPackage = nil
        guard let brew = brewURL, packages.contains(where: { $0.id == package.id }) else { return }
        brewNote = "正在更新 \(package.name)…"
        run(model, executable: brew, arguments: ["upgrade", package.cask ? "--cask" : "--formula", package.name],
            title: "執行 Homebrew 更新：\(package.name)", timeout: 1800) { [weak self] _, rc in
            guard let self = self else { return }
            self.brewNote = rc == 0 ? "更新程序完成；請重新檢查。詳情見記錄。" : "更新未完成或已取消；請查看詳細結果，再重新檢查。"
            self.packages = []
        }
    }
    func checkStore(_ model: AppModel) {
        guard let path = ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            storeNote = "未安裝 mas。請按「App Store 更新」檢查並安裝更新。"; return
        }
        storeNote = "正在檢查 App Store…"
        run(model, executable: URL(fileURLWithPath: path), arguments: ["outdated"], title: "檢查 App Store 更新") { [weak self] data, rc in
            guard rc == 0 else { self?.storeNote = "檢查失敗或已取消；請在 App Store 查看。"; return }
            let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            self?.storeNote = result.isEmpty ? "mas 未回報可更新項目；仍可在 App Store 核對。" : result
        }
    }
    func checkFeed(_ app: InstalledSoftware, model: AppModel) {
        guard let feed = app.feed, feed.scheme?.lowercased() == "https", feed.host != nil,
              feed.user == nil, feed.password == nil else {
            feedResults[app.id] = "更新來源不是有效 HTTPS；請在 App 內檢查。"; return
        }
        feedResults[app.id] = "正在檢查…"
        // No redirects, cookies or downloaded executable. Limit time and response size.
        run(model, executable: URL(fileURLWithPath: "/usr/bin/curl"),
            arguments: ["--disable", "--fail", "--silent", "--show-error", "--proto", "=https",
                        "--connect-timeout", "10", "--max-time", "25", "--max-filesize", "2097152", feed.absoluteString],
            title: "檢查 \(app.name) 更新來源", timeout: 30) { [weak self] data, rc in
                guard let self = self else { return }
                guard rc == 0, data.count <= 2_097_152 else {
                    self.feedResults[app.id] = "來源無法讀取或已取消；請在 App 內檢查。"; return
                }
                do {
                    let releases = try AppcastReader().read(data)
                    let os = ProcessInfo.processInfo.operatingSystemVersion
                    let system = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
                    let newer = releases.filter {
                        $0.channel.isEmpty && AppcastReader.newer($0.version, than: app.version) &&
                        ($0.minimumOS.isEmpty || (AppcastReader.numericVersion($0.minimumOS) && $0.minimumOS.compare(system, options: .numeric) != .orderedDescending))
                    }.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
                    self.feedResults[app.id] = newer.first.map { "來源提供 \($0.version)；請開啟 App 核對相容性並更新。" }
                        ?? "未找到可比較的較新穩定版本；請在 App 內核對。"
                } catch { self.feedResults[app.id] = "來源格式無法辨識；請在 App 內檢查。"; }
            }
    }
    func readLogin(_ model: AppModel) {
        loginItems = []; loginNote = "正在讀取；macOS 可能要求允許控制 System Events。"
        // JSON preserves names and paths containing tabs, quotes or newlines. This script never modifies items.
        let script = """
        var se = Application('System Events');
        JSON.stringify(se.loginItems().map(function(item) {
            return {name: item.name(), path: item.path() || '', hidden: item.hidden()};
        }));
        """
        run(model, executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-l", "JavaScript", "-e", script], title: "讀取登入項目", timeout: 45) { [weak self] data, rc in
                guard let self = self else { return }
                guard rc == 0 else { self.loginNote = "未能讀取或已取消。可到系統設定管理；拒絕自動化權限不代表沒有登入項目。"; return }
                do {
                    self.loginItems = try JSONDecoder().decode([LoginEntry].self, from: data)
                    self.loginNote = "傳統登入項目：\(self.loginItems.count) 項。新式背景項目請在系統設定查看。"
                } catch { self.loginNote = "登入項目回應無法辨識。"; }
            }
        readAgents()
    }
    private func readAgents() {
        let fm = FileManager.default
        let roots = [(fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"), "使用者"),
                     (URL(fileURLWithPath: "/Library/LaunchAgents"), "所有使用者"),
                     (URL(fileURLWithPath: "/Library/LaunchDaemons"), "系統背景服務")]
        agents = roots.flatMap { root, scope in
            (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "plist" }.map {
                AgentEntry(url: $0, label: $0.deletingPathExtension().lastPathComponent, scope: scope)
            } ?? []
        }.sorted { $0.label < $1.label }
    }
    func readAccessories(_ model: AppModel) {
        accessories = []; accessoryNote = "正在讀取藍牙配件…"
        run(model, executable: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
            arguments: ["SPBluetoothDataType", "-json"], title: "讀取配件電量", timeout: 60) { [weak self] data, rc in
                guard let self = self else { return }
                guard rc == 0 else { self.accessoryNote = "讀取失敗或已取消；不能判定配件電量。"; return }
                do {
                    self.accessories = try SystemData.accessories(data)
                    self.accessoryNote = "讀取時間：\(Date().formatted(date: .omitted, time: .standard))。未連線配件數據可能為舊資料。"
                } catch { self.accessoryNote = "此 macOS 回應格式未支援；可在藍牙設定查看。"; }
            }
    }
    func openLoginSettings() {
        let modern = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13
        let link = modern ? "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
                          : "x-apple.systempreferences:com.apple.preferences.users"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}
