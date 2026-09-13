# Harbour — Monterey GUI for Mole

開發預覽 0.2.0。目標：Intel MacBook 2016、macOS Monterey 12.7.6。

這份交付是 SwiftUI 原始碼，**並非已編譯、已測試的 App**。產生環境為 Linux，沒有 Apple SDK 或 Swift 編譯器；macOS 編譯、UI、真實 Mole 整合及實機測試仍待完成。

## 已實作

- 原生側邊欄、系統深淺色、繁體中文。
- 調用已安裝的 Mole：status、analyze、clean、uninstall、history。
- CPU／記憶體圖形、資料夾容量列表、Finder 定位、原始輸出。
- 獨立參數啟動（不使用 shell 插值）、錯誤顯示、停止、5 分鐘逾時、16 MB 輸出限制。
- 真正執行使用者層清理；先 dry-run 預覽，再由 GUI 確認。
- 掃描已安裝 App、多選、dry-run 移除預覽、最後確認及真正移到垃圾桶。
- Intel .app／.dmg 打包腳本。

## 在 Mac 建置

1. 安裝與 Monterey 相容的 Xcode 14.2 或 Swift 5.7+ Command Line Tools。
2. 按 https://github.com/tw93/Mole#quick-start 安裝 Mole CLI。
3. Terminal 進入本資料夾，執行 `bash scripts/build.command`。
4. 成功後開啟 `dist/Harbour.app`。設定中可選擇 `mo` 執行檔，Intel 通常在 `/usr/local/bin/mo`。
5. 選頁面再按更新資料／掃描清理預覽。

腳本使用本機 ad-hoc 簽署，沒有 Developer ID 公證。跨電腦分發仍需正式簽署／公證或按 macOS 的使用者允許流程開啟。

## 清理與權限

`mo clean` 在 GUI 非互動環境會自動完成使用者層清理；只有已有有效 sudo session 時才包括系統層清理。`mo uninstall` 如需管理員權限，Mole 自己會顯示原生密碼視窗。Harbour 不讀取或保存密碼。

操作紀錄目前顯示 JSON。監控為按鈕取得快照。系統維護及清理白名單 GUI 尚未接入。

下一步必須先在 macOS 編譯修正、確認最新 CLI 回傳 schema、測試權限不足／取消／大型掃描，再接入清理執行與權限處理。

## Attribution

Mole: https://github.com/tw93/Mole — tw93 and contributors, GPL-3.0.
Harbour is an independent frontend, not the official Mole for Mac. No upstream source or binary is bundled. This project's original source is provided under MIT; any later inclusion of upstream code must retain its applicable license.
