import SwiftUI
import AppKit
import HarbourCore

extension Page {
    var planetName: String {
        switch self {
        case .status, .accessories, .fans: return "太陽"
        case .clean, .purge, .installer, .external: return "地球"
        case .uninstall, .updates, .login: return "火星"
        case .optimize: return "水星"
        case .disk: return "木星"
        default: return ""
        }
    }
    var planetColor: Color {
        switch self {
        case .status, .accessories, .fans: return .orange
        case .clean, .purge, .installer, .external: return .blue
        case .uninstall, .updates, .login: return .red
        case .optimize: return .gray
        case .disk: return .brown
        default: return .gray
        }
    }
}

struct PlanetOrb: View {
    let page: Page
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [page.planetColor.opacity(0.25), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.7))
                .frame(width: size * 1.5, height: size * 1.5)
            Circle().fill(LinearGradient(colors: [page.planetColor.opacity(0.45), page.planetColor, .black.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.7))
                .frame(width: size, height: size)
            if page == .disk {
                Ellipse().stroke(page.planetColor.opacity(0.8), lineWidth: max(2, size * 0.08))
                    .frame(width: size * 1.55, height: size * 0.4).rotationEffect(.degrees(-25))
            }
            if page == .clean {
                Image(systemName: "globe.asia.australia.fill").resizable().scaledToFit()
                    .foregroundColor(.mint.opacity(0.7)).frame(width: size * 0.85, height: size * 0.85)
            }
        }.frame(width: size * 1.55, height: size * 1.5).accessibilityHidden(true)
    }
}

struct PlanetHeader: View {
    let page: Page
    var body: some View {
        HStack(spacing: 20) {
            PlanetOrb(page: page, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(page.planetName.isEmpty ? "Harbour" : page.planetName).font(.caption).foregroundColor(.secondary)
                Text(page.rawValue).font(.system(size: 26, weight: .semibold, design: .rounded))
            }
            Spacer()
        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SolarOverview: View {
    @ObservedObject var model: AppModel
    private let pages: [Page] = [.clean, .updates, .disk, .login, .accessories, .fans]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("星體各循其軌，Harbour 照看 Mac 的日常").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                ForEach(pages) { page in
                    Button { model.navigate(to: page) } label: {
                        VStack(spacing: 8) {
                            PlanetOrb(page: page, size: 46)
                            Text(page.planetName).font(.caption).foregroundColor(.secondary)
                            Text(page.rawValue).font(.headline).foregroundColor(.primary)
                        }.frame(maxWidth: .infinity).padding(16)
                            .background(RoundedRectangle(cornerRadius: 18).fill(page.planetColor.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(page.planetColor.opacity(0.18)))
                    }.buttonStyle(.plain).help("開啟\(page.rawValue)").disabled(!model.canNavigate)
                }
            }
        }
    }
}

struct SoftwareUpdatesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tools: SystemTools
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Homebrew") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("檢查本機目錄") { tools.checkBrew(model) }
                        Button("更新目錄並檢查") { tools.checkBrew(model, refresh: true) }
                    }.disabled(model.runner.busy)
                    Text(tools.brewNote).font(.caption).foregroundColor(.secondary)
                    ForEach(tools.packages) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text("\(item.installed) → \(item.latest) · \(item.cask ? "App" : "命令工具")").font(.caption)
                            }
                            Spacer()
                            Button("更新…") { tools.pendingPackage = item }.disabled(model.runner.busy)
                        }.padding(.vertical, 4)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("App Store") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("檢查（mas）") { tools.checkStore(model) }.disabled(model.runner.busy)
                        Link("App Store 更新", destination: URL(string: "macappstore://showUpdatesPage")!)
                    }
                    Text(tools.storeNote).font(.caption).textSelection(.enabled)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Sparkle 與其他 App") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("掃描已安裝 App") { tools.scanSoftware() }.disabled(tools.scanning || model.runner.busy)
                        if tools.scanning { ProgressView().controlSize(.small) }
                        TextField("搜尋 App 或更新來源", text: $query)
                    }
                    Text(tools.softwareNote).font(.caption).foregroundColor(.secondary)
                    Text("檢查來源會連線至 App 提供的更新網址。安裝、簽章驗證及最終相容性由 App 自己的更新器處理。").font(.caption).foregroundColor(.secondary)
                    ForEach(tools.software.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query) }) { app in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.name).font(.headline)
                                    Text("\(app.version) · \(app.source)").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if app.feed != nil {
                                    Button("檢查來源") { tools.checkFeed(app, model: model) }.disabled(model.runner.busy)
                                }
                                Button("開啟 App") { NSWorkspace.shared.open(app.url) }
                            }
                            if let result = tools.feedResults[app.id] { Text(result).font(.caption).foregroundColor(.secondary) }
                            DisclosureGroup("位置及來源") {
                                Text(app.url.path).font(.caption).textSelection(.enabled)
                                if let feed = app.feed { Text(feed.absoluteString).font(.caption).textSelection(.enabled) }
                            }
                            Divider()
                        }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.alert(item: $tools.pendingPackage) { item in
            Alert(title: Text("更新 \(item.name)？"),
                  message: Text("\(item.installed) → \(item.latest)\nHomebrew 可能同時更新必要依賴。請先儲存工作並關閉相關 App。需要密碼或互動的安裝請在 Terminal 完成。"),
                  primaryButton: .default(Text("確認更新")) { tools.upgrade(item, model: model) },
                  secondaryButton: .cancel(Text("取消")))
        }
    }
}

struct LoginItemsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tools: SystemTools
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("讀取登入項目") { tools.readLogin(model) }.disabled(model.runner.busy)
                Button("在系統設定管理") { tools.openLoginSettings() }
            }
            Text(tools.loginNote).foregroundColor(.secondary)
            ForEach(tools.loginItems) { item in
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name).font(.headline)
                            Text(item.hidden ? "登入時隱藏" : "登入時顯示").font(.caption)
                            Text(item.path).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        if !item.path.isEmpty {
                            Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                        }
                    }.padding(8)
                }
            }
            DisclosureGroup("LaunchAgents／LaunchDaemons 檔案（\(tools.agents.count)）") {
                Text("檔案存在不代表目前正在執行或已啟用；不能據此判定是否安全。停用請使用系統設定或原 App。讀取不到的資料夾不會出現在清單。")
                    .font(.caption).foregroundColor(.secondary).padding(.vertical, 8)
                ForEach(tools.agents) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.label).lineLimit(1)
                            Text(entry.scope).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                    }.padding(.vertical, 4)
                }
            }
        }
    }
}

struct AccessoriesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tools: SystemTools
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("更新配件電量") { tools.readAccessories(model) }.disabled(model.runner.busy)
                Link("藍牙設定", destination: URL(string: "x-apple.systempreferences:com.apple.preferences.Bluetooth")!)
            }
            Text(tools.accessoryNote).font(.caption).foregroundColor(.secondary)
            if tools.accessories.isEmpty { Text("尚無可顯示配件。請連接配件後更新；並非所有裝置都會向 macOS 提供電量。").foregroundColor(.secondary) }
            ForEach(tools.accessories) { item in
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "wave.3.right").foregroundColor(.cyan)
                            Text(item.name).font(.headline)
                            Spacer()
                            Text(item.connected ? "已連線" : "未連線 · 可能為舊資料").font(.caption).foregroundColor(.secondary)
                        }
                        if item.levels.isEmpty { Text("電量未提供").foregroundColor(.secondary) }
                        ForEach(item.levels.indices, id: \.self) { index in
                            HStack {
                                Text(item.levels[index].label).frame(width: 60, alignment: .leading)
                                ProgressView(value: item.levels[index].value, total: 100)
                                Text(String(format: "%.0f%%", item.levels[index].value)).monospacedDigit().frame(width: 48, alignment: .trailing)
                            }
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct FanStatusView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let thermal = dictionary(model.snapshot["thermal"])
        let rpm = SystemData.positiveReading(thermal["fan_speed"])
        let fans = SystemData.positiveReading(thermal["fan_count"])
        return VStack(alignment: .leading, spacing: 16) {
            Button("更新風扇及溫度") { model.loadStatus(live: false) }.disabled(model.runner.busy)
            Text("唯讀狀態 · Harbour 不會調整轉速、寫入 SMC 或改動散熱設定。").font(.callout).foregroundColor(.secondary)
            GroupBox("風扇") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(rpm.map { String(format: "%.0f RPM", $0) } ?? "轉速未提供").font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(fans.map { String(format: "引擎回報 %.0f 個風扇", $0) } ?? "風扇數量未提供")
                    Text("此為引擎提供的單一轉速欄位，並非每個風扇的獨立讀數。0 或缺失值不能區分停止、不支援或無風扇機型。")
                        .font(.caption).foregroundColor(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                temperature("CPU", SystemData.positiveReading(thermal["cpu_temp"]))
                temperature("GPU", SystemData.positiveReading(thermal["gpu_temp"]))
                temperature("電池", SystemData.positiveReading(thermal["battery_temp"]))
            }
            Text("快照時間：\(display(model.snapshot["collected_at"]))").font(.caption).foregroundColor(.secondary).textSelection(.enabled)
            Text("讀數只反映快照時間，不能單憑轉速判斷散熱是否正常。").font(.caption).foregroundColor(.secondary)
        }
    }
    private func temperature(_ label: String, _ value: Double?) -> some View {
        GroupBox(label) {
            Text(value.map { String(format: "%.1f °C", $0) } ?? "未提供")
                .font(.title2).monospacedDigit().padding(8).frame(maxWidth: .infinity)
        }
    }
}
