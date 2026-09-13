# Harbour 0.3.0 — Mole 原生 GUI 開發預覽

目標：Intel MacBook 2016、macOS Monterey 12.7.6（最低設定 macOS 12）。

**這是原始碼交付，不是可直接安裝的 App。尚未在 macOS 編譯或實機驗證；不能視為已驗證的 Mole 全功能發行版。**

## 已接入的功能範圍

| 頁面 | 實作 |
| --- | --- |
| 系統監察 | 即時 CPU、記憶體及引擎提供的 GPU、磁碟、網絡、電池、溫度、程序等資料；不支援的硬件欄位可能缺省 |
| 磁碟分析 | 容量、大型檔案、排序搜尋、多選、Finder、Quick Look、確認後移到垃圾桶 |
| 清理 | dry-run 預覽、明確確認、真正清理、選擇管理員授權 |
| 移除 App | 同次掃描的精確路徑選取、預覽、原引擎移除流程、垃圾桶／永久模式 |
| 系統維護 | optimize 預覽及確認執行 |
| 開發檔案 | purge 分類與多選；近期／雲端項目預設不勾選 |
| 安裝檔 | 掃描、多選、預覽及永久刪除確認 |
| 外置磁碟 | 選取路徑、預覽及清理 |
| 紀錄 | 工作階段、刪除紀錄、搜尋與詳細資料 |
| 保護設定 | 清理／維護白名單、開發掃描路徑 |
| 設定 | 外置 CLI 安裝／更新／移除、版本檢查、Touch ID、shell completion、輸出匯出 |

使用固定 Mole 1.53.0 引擎；並非承諾覆蓋未來版本。更新外置 CLI 不會改動內置引擎。命令已有介面接線，端到端相容性仍須 Mac 測試。

## 下載後，在 Mac 建置

1. 解壓 ZIP。
2. 安裝支援 Monterey、附 Swift 5.7 或以上的 Apple 開發工具；已有相容工具可跳過。
3. 開啟 Terminal，輸入 `cd `（留一個空格），把解壓後的 `HarbourMac` 資料夾拖入 Terminal，按 Enter。
4. 執行 `bash scripts/build.command`。
5. 建置成功才會產生 `dist/Harbour-Intel.dmg`。開啟它，把 Harbour 拖入 Applications。

已附兩個 Darwin x86_64 引擎程式，不必先安裝 Mole CLI。自行重建引擎需要 Go 1.25+。打包使用 ad-hoc 簽署，沒有 Developer ID 公證；不應關閉 Gatekeeper 或 SIP。

另附 `.github/workflows/build-intel.yml`，供使用者自己的 GitHub repository 執行 Intel macOS 編譯及上傳 DMG artifact。本交付尚未執行此工作流程。

## 清理與權限

- 會真正刪除資料。首次測試請使用可丟棄的測試 App／資料夾及完整備份。
- 清理與維護要求先預覽；選取型操作要求最終確認。預覽不是交易鎖，實際執行仍由引擎重查路徑。
- 管理員密碼透過獨立系統提示交予 sudo，GUI 不保存密碼，不以 root 執行整個 App。
- 垃圾桶模式不保證所有子操作可復原：Homebrew zap 等可能永久刪除設定；purge／安裝檔清理亦可能永久刪除。
- 停止會終止工作程序群組，但已完成的刪除無法撤銷。
- Touch ID 須有相應硬件，不能假設 2016 年 MacBook 配備 Touch ID。

## 驗證狀態

已在 Linux 通過：Shell 語法、原生 GUI Swift 語法解析、Core 型別檢查、C worker 嚴格編譯、Python transport／程序取消測試。Go 引擎已交叉編譯為 Mach-O x86_64。

尚未完成：Apple SDK 型別檢查、SwiftUI 編譯及介面測試、macOS 打包／簽署、Monterey 真實權限及完整清理／移除流程。Linux `swift test` 因編譯器執行環境崩潰而失敗，不能當作 XCTest 通過。

Mac 發行前必測：`swift test`、`python3 Tests/test_transport.py`、建置腳本、拒絕密碼、途中取消、特殊字元路徑、失效預覽、大型掃描、垃圾桶回復、唯讀磁碟、Homebrew App、相同 bundle ID、無 Touch ID 硬件。

## 原始碼及授權

Harbour 是独立非官方前端。此整合發行包依 GPL-3.0 提供，見 LICENSE。

上游：<https://github.com/tw93/Mole>，tw93 and contributors。
固定 commit：`2ab192fb59674d12f95b95d46a13b956c50e8b1a`。

`Sources/HarbourMac/Resources/Engine` 包含引擎原始碼及授權。`scripts/prepare_engine.py` 記錄來源載入、GUI 選取與確認修改；引擎安全刪除 helpers 保留。`Sources/HarbourCore` 是 nonce／base64 訊息解析；`Sources/HarbourWorker` 是程序群組監督程式。
