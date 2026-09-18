import SwiftUI
import AppKit
import Combine
import HarbourCore

/// Opt-in, read-only sampler; independent of the main operation runner.
@MainActor final class HUDController: NSObject, ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey: "harbourHUDEnabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "harbourHUDEnabled")
            configure()
        }
    }
    @Published private(set) var metrics = HUDMetrics([:])
    @Published private(set) var note = "尚未讀取"
    private let runner = Runner()
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var timer: Timer?
    private var generation = UUID()
    var openWindow: (() -> Void)?
    var openSettings: (() -> Void)?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: HUDPanel(controller: self))
        configure()
    }
    private func configure() {
        generation = UUID()
        timer?.invalidate(); timer = nil
        if !enabled {
            runner.stop()
            popover.close()
            if let item = item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            metrics = HUDMetrics([:]); note = "已停用"
            return
        }
        if item == nil {
            let entry = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item = entry
            entry.button?.target = self
            entry.button?.action = #selector(togglePanel)
            entry.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            entry.button?.setAccessibilityLabel("Harbour 系統監察")
        }
        sample()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    private func sample() {
        renderTitle()
        guard enabled, !runner.busy else { return }
        let id = generation
        note = "正在讀取…"
        // One bounded snapshot, no persistent stream or unbounded output buffer.
        runner.start(runner.engineURL.appendingPathComponent("bin/status-go"), ["--json"], timeout: 30) { [weak self] data, rc in
            guard let self = self, self.enabled, self.generation == id else { return }
            if rc == 0, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.metrics = HUDMetrics(object)
                self.note = self.metrics.isFresh() ? "最近快照（每 10 秒嘗試更新）" : "資料已過期或缺少時間"
            } else {
                self.metrics = HUDMetrics([:])
                self.note = "讀取失敗；請重新開啟監察或查看系統監察頁。"
            }
            self.renderTitle()
        }
        if !runner.busy { note = "未能啟動監察：\(runner.outcome)" }
    }
    private func renderTitle() {
        let fresh = metrics.isFresh()
        if !fresh { note = "尚無有效近期快照" }
        item?.button?.title = "CPU \(HUDMetrics.percent(fresh ? metrics.cpu : nil)) · RAM \(HUDMetrics.percent(fresh ? metrics.memory : nil))"
        item?.button?.toolTip = note
    }
    @objc private func togglePanel() {
        guard let button = item?.button else { return }
        renderTitle()
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    func showWindow(settings: Bool = false) {
        popover.close()
        if settings { openSettings?() } else { openWindow?() }
    }
    func shutdown() {
        generation = UUID()
        timer?.invalidate(); timer = nil
        runner.stop(); popover.close()
        if let item = item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }
}

struct HUDPanel: View {
    @ObservedObject var controller: HUDController
    var body: some View {
        let metrics = controller.metrics
        let fresh = metrics.isFresh()
        VStack(alignment: .leading, spacing: 12) {
            Text("Harbour 系統監察").font(.headline)
            Text("CPU：\(HUDMetrics.percent(fresh ? metrics.cpu : nil))")
            Text("記憶體：\(HUDMetrics.percent(fresh ? metrics.memory : nil))")
            Text("接收：\(HUDMetrics.rate(fresh ? metrics.received : nil))")
            Text("傳送：\(HUDMetrics.rate(fresh ? metrics.sent : nil))")
            Text("所有介面合計，VPN 等介面可能重複計算；不是 Internet 測速。").font(.caption).foregroundColor(.secondary)
            Text(controller.note).font(.caption).foregroundColor(.secondary)
            if let date = metrics.collectedAt { Text(date, style: .time).font(.caption) }
            Divider()
            HStack {
                Button("開啟 Harbour") { controller.showWindow() }
                Button("設定") { controller.showWindow(settings: true) }
            }
            HStack {
                Button("停用 HUD") { controller.enabled = false; controller.showWindow(settings: true) }
                Spacer()
                Button("結束") { NSApp.terminate(nil) }
            }
        }.padding(16).frame(width: 310)
    }
}

struct HUDSettings: View {
    @ObservedObject var controller: HUDController
    var body: some View {
        Toggle("啟用選單列 CPU／記憶體／網絡監察", isOn: $controller.enabled)
    }
}

/// Capture only the main Harbour window, not the HUD or a transient dialog.
struct MainWindowCapture: NSViewRepresentable {
    let capture: (NSWindow) -> Void
    func makeNSView(context: Context) -> CaptureView { CaptureView(capture: capture) }
    func updateNSView(_ nsView: CaptureView, context: Context) { nsView.capture = capture }
    final class CaptureView: NSView {
        var capture: (NSWindow) -> Void
        init(capture: @escaping (NSWindow) -> Void) { self.capture = capture; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window = window { capture(window) }
        }
    }
}
