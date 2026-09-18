# Harbour 044 — 唯讀磁碟 Treemap（2026-09-17）

**基線：** `feat/044-disk-treemap` @ `0ce1527`。只留未提交 diff；不 commit／push／安裝／執行真實引擎。原有 parity 草稿不改。

## Producer 核對

- `HarbourApp.swift`：`DiskReport` 為 `path / entries? / large_files? / total_size / total_files?`；`DiskEntry` 為 `name / path / size: Int64 / is_dir?`。`analyze(path)` 已有 busy guard，呼叫現有 `analyze-go --json <folder>`。
- `cmd/analyze/json.go` 目錄模式呼叫 `scanPathConcurrentAllEntries`；`scanner.go` 的 `entryLimit = 0` 保留全部回傳 entries，不套用 TUI 的 30 項截斷。
- `total_size` 為 scanner 累積的項目大小，不是 volume capacity／free space；傳送逾時等情況下不能保證等於回傳 entries 大小之和。資料亦可能包含快取量測值。
- `large_files` 為另一份可與目錄 entries 重疊的遞迴大檔清單（heap 上限 20，亦有 Spotlight 替代路徑）。地圖完全不使用此欄位。

## 實作計劃與邊界

1. 先新增 Core XCTest：幾何比例／守恆／不重疊、空／零／負值、無效邊界、Int64 極值、排序與路徑去重、大量項目聚合；全部使用明確 synthetic fixtures。
2. 新增 `HarbourCore/DiskTreemap.swift`：純 Double 幾何二元分割；大小降序、同大小依路徑排序。最多 256 塊，超量保留前 255 項及有完整 membership 的「其他」聚合，不丟棄任何正大小 unique path。Double 只供面積計算，避免 Int64 加總溢位；不膨脹 tiny tiles，低於像素／浮點精度的項目仍在清單。
3. 新增 `HarbourMac/DiskTreemapView.swift`：GeometryReader / Path，原生 Button、目錄 busy guard → `model.analyze(path)`、Finder context menu；「其他」展開完整唯讀清單。地圖固定依回傳正大小 entries，明文標示不受搜尋／大型檔案／名稱排序影響，不代表整個磁碟或剩餘容量；零與無效大小仍有清單 fallback。
4. `DataViews.swift` 僅新增 import 與 DiskView 的地圖插入點；保留原清單、選取、Quick Look、Finder、垃圾桶及確認行為。不改 engine、Runner、AppModel、清理、歷史或狀態邏輯。
5. 新增 Mac integration XCTest：解碼 fixture、拒用 overlapping large_files、空報告、busy/file action gate、濾鏡獨立與選取不變；closure spy 不啟動引擎。

## 實際驗證與剩餘工作

- `PYTHONDONTWRITEBYTECODE=1 python3 Tests/test_transport.py`：已讀取測試後執行，11 項通過；僅測試 transport／synthetic ledger／臨時 worker，無真實 scan／cleanup。
- `git diff --check`：通過；tracked diff 僅 DataViews 的兩行新增。
- `swift build`：失敗，`swift: command not found`。新增 6 個 Core、4 個 Mac XCTest **尚未執行**；不可把便攜測試當作 SwiftUI 編譯或 GUI 驗證。
- Parent：在授權 macOS CI 執行 `swift test`／app build，先做規格與程式碼 review，未通過不得稱為完成驗收。
- Mac 人工驗收待辦：resize、Keyboard Navigation／VoiceOver、長名稱與細 tile、其他聚合完整清單、busy 禁止 drilldown、Finder reveal、搜尋／名稱排序／大型檔案 scope。保持原垃圾桶流程，這個里程碑不需對真實資料測試刪除。
