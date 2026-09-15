# Harbour — Planet UI for Mole

Harbour 0.4.1 是支援 Intel Mac / macOS 12+ 的原生 SwiftUI GUI，內置固定版本 Mole 1.53.0 引擎。

## 太陽系導覽

太陽為系統總覽；地球清理；火星管理軟體；木星瀏覽磁碟；土星查看登入項目；天王星查看配件電量；海王星顯示唯讀風扇及溫度。保留原有預覽、選取及最後確認流程。

## 新功能與實際範圍

- **Homebrew 更新**：使用本機目錄檢查 formula/cask；可另外更新 Homebrew 目錄，再檢查。每個安裝操作需要確認。Homebrew 可能更新必要依賴；需要密碼／互動的安裝請使用 Terminal。自動更新 App、latest cask 或釘選套件可能略過，零筆結果不代表所有 App 均最新。
- **App Store**：已裝 mas 時執行 outdated；缺少 mas 或檢查失敗時顯示原因。安裝交由 App Store。
- **Sparkle**：掃描 /Applications 及 ~/Applications，辨識 SUFeedURL。按「檢查來源」才連線至該 App 的 HTTPS feed；解析穩定版本及最低系統版本。僅比較數字版本；結果為來源提示，不是完整硬體、架構或更新資格判定。更新交回 App，Harbour 不下載 enclosure、不繞過簽章驗證。來源轉址或格式不支援時請在 App 內檢查。
- **登入項目**：使用唯讀 JXA 列出傳統登入項目；可能要求 System Events 自動化權限。列出使用者／全機 LaunchAgents 與 LaunchDaemons 檔案，檔案存在不代表啟用或正在執行。新式背景項目、啟用／停用在系統設定管理；不刪 plist、不執行 bootout。
- **配件電量**：直接解析 system_profiler 的 Bluetooth JSON，分別顯示左右耳／充電盒、連線狀態及讀取時間。不提供電量時顯示未知，0% 保留；未連線項目明確標示可能為舊資料。
- **風扇狀態**：讀取內置 Mole 的 thermal 快照。顯示單一引擎轉速欄位、風扇數量、CPU/GPU/電池溫度及時間；非逐風扇資料。零值與缺失值均標示未提供，不推定風扇停止或無風扇。無 SMC 寫入、無調速、無提權。

所有磁碟清理及掃描在本機執行；使用者主動檢查更新時會連線至對應更新服務。

## 原有功能

系統快照／持續監察、磁碟容量分析、Finder 定位、操作紀錄、清理預覽、App／開發檔案／安裝檔選取、最後確認、系統維護、外置磁碟、保護清單與外部 CLI 管理。停止會終止工作程序群組，但已完成的修改不會自動還原。

## 建置與測試

在 Intel Mac 安裝 Swift 5.7+ / Xcode Command Line Tools：

    swift test
    python3 Tests/test_transport.py
    bash scripts/build.command

產物為 dist/Harbour-Intel.dmg。打包使用內置引擎，毋須先安裝外部 Mole CLI。外部 CLI 可另行設定。GitHub pull request 會執行 macOS 測試及 Intel DMG 建置。

打包使用 ad-hoc 簽署，並未 Developer ID 公證。跨電腦執行須遵循 macOS 正常使用者允許流程。

## 實機驗收

CI 無法驗證私人 Mac 的 TCC 權限及硬體。請在 macOS 12 實測：

1. 深／淺色、窄視窗、鍵盤導覽；原有清理仍先預覽再確認。
2. 無 Homebrew／mas、離線、檢查失敗；不能顯示成全部最新。
3. Homebrew 單項確認／取消、更新後重新掃描；不得批量升級未選套件（必要依賴除外）。
4. Sparkle 來源失敗、過新 macOS 要求及非數字版本，均能交回原 App 核對。
5. 接受／拒絕 System Events 權限；核對登入項目，管理時開啟正確系統頁面。
6. AirPods 左右耳／充電盒、滑鼠、0%／無電量及斷線配件。
7. 有／無風扇及無感測器機型，不將缺失資料顯示為正常或風扇停止。

## Attribution / License

Harbour 是獨立開源前端，並非官方 Mole for Mac。
內置 Mole 原始碼及 Intel 執行檔來自 tw93 與貢獻者，依 GPL-3.0 發佈；版本來源見 Sources/HarbourMac/Resources/Engine/UPSTREAM.json。本 repository 的 LICENSE 為 GPL-3.0；保留上游版權及授權。

- Mole: https://github.com/tw93/Mole
- Homebrew commands: https://docs.brew.sh/Manpage
- Sparkle metadata: https://sparkle-project.org/documentation/publishing/
