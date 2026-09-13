# Harbour — Monterey GUI for Mole

Harbour 0.3.1（Intel Mac、macOS Monterey 12.7.6）。這是一個以 SwiftUI 製作的繁體中文 GUI，讓普通用家可以先預覽、再確認，安全地使用 Mole 的清理及維護功能。

GitHub Release 會提供由 macOS Intel runner 建置的 `Harbour-Intel.dmg`；亦可在 Mac 上按下方指令自行建置。

## 已實作

- 原生側邊欄、系統深淺色、繁體中文。
- 調用已安裝的 Mole：status、analyze、clean、uninstall、history。
- CPU／記憶體圖形、資料夾容量列表、Finder 定位、原始輸出。
- 獨立參數啟動（不使用 shell 插值）、錯誤顯示、停止、5 分鐘逾時、16 MB 輸出限制。
- 真正執行使用者層清理；先 dry-run 預覽，再由 GUI 確認。
- 掃描已安裝 App、開發檔案及安裝檔，多選、最後確認及真正移除／移到垃圾桶。
- 掃描時顯示目前階段、已用時間及「尚未刪除」提示；結果以「發現什麼／下一步做什麼」顯示，技術路徑收在可展開的詳細資料。
- 系統維護、外置磁碟、白名單、Touch ID 狀態及 shell completion GUI。
- Intel .app／.dmg 打包腳本。

## 基本使用流程

1. 從左側選擇「清理」、「移除 App」、「開發檔案」或「安裝檔」。
2. 先按「預覽（不刪除）」或「開始掃描」，等待畫面顯示掃描完成。
3. 如有清單，勾選要處理的項目，再按「下一步：查看會處理的資料」。
4. 閱讀最後確認卡片，按「確認執行」才會真正修改資料；不確定就按「取消並重新掃描」。

## 在 Mac 建置

1. 安裝與 Monterey 相容的 Xcode 14.2 或 Swift 5.7+ Command Line Tools。
2. 按 https://github.com/tw93/Mole#quick-start 安裝 Mole CLI。
3. Terminal 進入本資料夾，執行 `bash scripts/build.command`。
4. 成功後開啟 `dist/Harbour.app`。設定中可選擇 `mo` 執行檔，Intel 通常在 `/usr/local/bin/mo`。
5. 選頁面再按更新資料／掃描清理預覽。首次 App 掃描可能需幾分鐘；掃描期間可以按「停止」。

腳本使用本機 ad-hoc 簽署，沒有 Developer ID 公證。跨電腦分發仍需正式簽署／公證或按 macOS 的使用者允許流程開啟。

## 清理與權限

`mo clean` 在 GUI 非互動環境會自動完成使用者層清理；只有已有有效 sudo session 時才包括系統層清理。`mo uninstall` 如需管理員權限，Mole 自己會顯示原生密碼視窗。Harbour 不讀取或保存密碼。

操作紀錄保留原始詳細資料，方便需要時檢查；一般使用者只需跟隨畫面上的進度及下一步提示。監控可取得單次快照或每 2 秒更新。

## Attribution

Mole: https://github.com/tw93/Mole — tw93 and contributors, GPL-3.0.
Harbour is an independent frontend, not the official Mole for Mac. No upstream source or binary is bundled. This project's original source is provided under MIT; any later inclusion of upstream code must retain its applicable license.
