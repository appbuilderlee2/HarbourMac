import SwiftUI
import AppKit

struct AppearanceSettingsView: View {
    let selection: Binding<String>

    var body: some View {
        GroupBox("外觀") {
            Picker("外觀", selection: selection) {
                Text("跟隨系統").tag("system")
                Text("淺色").tag("light")
                Text("深色").tag("dark")
            }
            .pickerStyle(.segmented)
        }
    }
}

struct EngineSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GroupBox("引擎與版本") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.versionInfo)
                Text("GUI 內置相容引擎，可直接使用。外部 mo 指令可獨立安裝或更新。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("檢查官方版本", action: model.checkLatest)
                        .disabled(model.busyNetwork)
                    Link("官方發布紀錄", destination: URL(string: "https://github.com/tw93/Mole/releases")!)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ExternalCLISettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GroupBox("外部 Mole CLI") {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.cliPath)
                    .font(.caption)
                    .textSelection(.enabled)

                HStack {
                    Button("選擇 mo…", action: model.chooseCLI)
                    Button("偵測版本", action: model.cliVersion)
                    Button("安裝 CLI", action: {
                        model.bridge("install", apply: true, title: "安裝 Mole CLI", phase: "正在下載官方 CLI…")
                    })
                    Button("更新 CLI", action: model.updateCLI)
                }

                HStack {
                    Button("預覽移除 Mole", action: {
                        model.bridge("remove", apply: false, title: "預覽移除 Mole", phase: "正在整理可移除的檔案…")
                    })
                    Button("移除 Mole CLI／設定", action: {
                        model.bridge("remove", apply: true, title: "移除 Mole CLI／設定", phase: "正在準備移除…")
                    })
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TouchIDSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GroupBox("Touch ID 與命令補完") {
            VStack(alignment: .leading, spacing: 10) {
                Text("2016 年 12 吋 MacBook 沒有 Touch ID；配備 Touch Bar 的 MacBook Pro 才有相關硬件。")

                HStack {
                    Button("Touch ID 狀態", action: {
                        model.bridge("touchid", apply: false, args: ["status"], title: "查看 Touch ID 狀態", phase: "正在檢查硬件支援…")
                    })
                    Button("啟用", action: {
                        model.bridge("touchid", apply: true, args: ["enable"], title: "啟用 Touch ID sudo", phase: "正在準備修改設定…")
                    })
                    Button("停用", action: {
                        model.bridge("touchid", apply: true, args: ["disable"], title: "停用 Touch ID sudo", phase: "正在準備修改設定…")
                    })
                }

                HStack {
                    Text("產生補完腳本：")
                    ForEach(["zsh", "bash", "fish"], id: \.self) { shell in
                        Button(shell) {
                            model.bridge("completion", apply: false, args: [shell], title: "產生 \(shell) 補完腳本", phase: "正在產生腳本…")
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AppAttributionView: View {
    var body: some View {
        Text("Harbour 0.4.1 · Intel / macOS 12+\nMole © tw93 與貢獻者 · GPL-3.0\n本 App 為獨立開源 GUI，並非官方 Mole for Mac。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
