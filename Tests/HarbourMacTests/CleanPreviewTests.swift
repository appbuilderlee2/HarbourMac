import XCTest
import HarbourCore
@testable import HarbourMac

final class CleanPreviewTests: XCTestCase {
    @MainActor func feed(_ model: AppModel, rc: Int32 = 0) throws {
        for (kind, fields) in [
            ("clean_preview_begin", ["1", "mole.clean.deduplicated-ledger", "false"]),
            ("clean_preview_item", ["0", "id", "App caches", "/fixture", "0", "1", "false"]),
            ("clean_preview_end", ["1", "0", "0"])
        ] {
            let line = (["@@HARBOUR:test", kind] + fields.map { Data($0.utf8).base64EncodedString() }).joined(separator: "\t")
            let event = try XCTUnwrap(BridgeEvent.parse(line, token: "test"), "Fixture line must parse: \(kind)")
            model.handle(event)
        }
        model.finishCleanPreview(exitCode: rc)
    }

    func testNewScanClearsRowsAndAllOldValidity() async throws {
        try await MainActor.run {
            let model = AppModel()
            model.navigate(to: Page.clean)
            model.beginCleanPreview()
            try self.feed(model)
            XCTAssertTrue(model.canApply)
            XCTAssertEqual(model.cleanPreview.items.count, 1)
            let firstItem = try XCTUnwrap(model.cleanPreview.items.first)
            XCTAssertEqual(model.cleanSizeText(firstItem), "未知")
            model.admin = true
            model.beginCleanPreview()
            XCTAssertTrue(model.cleanPreview.items.isEmpty)
            XCTAssertFalse(model.canApply)
            model.finishCleanPreview(exitCode: 0)
            XCTAssertFalse(model.canApply)
            model.admin = false
            XCTAssertFalse(model.canApply, "Changing settings back cannot revive a previous scan")
        }
    }

    func testIncompleteAndMalformedPreviewNeverAuthorizeApply() async throws {
        try await MainActor.run {
            let model = AppModel()
            model.navigate(to: Page.clean)
            model.beginCleanPreview()
            try self.feed(model, rc: 130)
            XCTAssertFalse(model.canApply)
            model.beginCleanPreview()
            model.runner.onInvalidPreview?()
            try self.feed(model)
            XCTAssertFalse(model.canApply)
            XCTAssertFalse(model.selecting)
            XCTAssertTrue(model.rows.isEmpty)
            XCTAssertTrue(model.confirmationMessage.contains("重新掃描"))
        }
    }

    func testRunGateIgnoresStaleAndCompletedCallbacks() async {
        await MainActor.run {
            let runner = Runner()
            runner.busy = true
            let current = runner.runID
            runner.receive(for: UUID()) { $0.log = "stale"; $0.busy = false }
            XCTAssertTrue(runner.busy)
            XCTAssertTrue(runner.log.isEmpty)
            runner.receive(for: current) { $0.log = "current" }
            XCTAssertEqual(runner.log, "current")
            runner.busy = false
            runner.receive(for: current) { $0.log = "late tail" }
            XCTAssertEqual(runner.log, "current")
        }
    }

    func testSaveConfigNoOpWhenBusyOrNotLoaded() async throws {
        try await MainActor.run {
            let model = AppModel()
            model.navigate(to: Page.clean)
            try self.successfulPreview(model)
            let generation = model.previewGeneration
            model.configLoaded = false
            model.saveConfig()
            XCTAssertTrue(model.canApply)
            XCTAssertEqual(model.previewGeneration, generation)
            model.configLoaded = true
            model.runner.busy = true
            model.saveConfig()
            XCTAssertEqual(model.previewGeneration, generation)
            model.runner.busy = false
            XCTAssertTrue(model.canApply)
            XCTAssertTrue(model.runner.log.isEmpty)
        }
    }

    // MARK: - saveConfig invalidation

    /// Feeds a successful preview and stamps it, without running the Runner:
    /// begin + structured events + finish mirror the real bridge() path.
    @MainActor func successfulPreview(_ model: AppModel) throws {
        model.beginCleanPreview()
        try self.feed(model)
        XCTAssertTrue(model.canApply, "Fixture precondition: preview is valid before the save")
    }

    @MainActor func testSuccessfulConfigSaveInvalidatesPreviewAndTogglingCannotResurrect() throws {
        let model = AppModel()
        model.navigate(to: Page.clean)
        try self.successfulPreview(model)
        model.configLoaded = true
        model.handleSaveConfigResult(0)
        XCTAssertFalse(model.canApply, "Saved config must expire the previous successful preview")
        XCTAssertEqual(model.cleanPreview.items.count, 1, "Invalidation retains the previous report for inspection")
        XCTAssertTrue(model.cleanPreview.isInvalid)
        XCTAssertTrue(model.notice.contains("重新掃描"))
        // Toggling admin (or any previewKey component) cannot resurrect it.
        model.admin = true
        XCTAssertFalse(model.canApply)
        model.admin = false
        XCTAssertFalse(model.canApply)
        model.navigate(to: Page.protection)
        model.navigate(to: Page.clean)
        XCTAssertFalse(model.canApply, "Returning to clean cannot revive the old preview")
        // A fresh successful scan restores eligibility.
        try self.successfulPreview(model)
        XCTAssertTrue(model.canApply)
    }

    @MainActor func testFailedConfigSaveAlsoInvalidatesPreviewFailClosed() throws {
        let model = AppModel()
        model.navigate(to: Page.clean)
        try self.successfulPreview(model)
        model.configLoaded = true
        model.handleSaveConfigResult(1)
        XCTAssertFalse(model.canApply, "Uncertain save outcome must fail closed")
        XCTAssertTrue(model.cleanPreview.isInvalid)
        model.handleSaveConfigResult(130)
        XCTAssertFalse(model.canApply)
        // A fresh successful scan restores eligibility even after failures.
        try self.successfulPreview(model)
        XCTAssertTrue(model.canApply)
    }

    @MainActor func testSaveResultIsNoOpWhenConfigNotLoaded() throws {
        let model = AppModel()
        model.navigate(to: Page.clean)
        try self.successfulPreview(model)
        model.configLoaded = false
        model.handleSaveConfigResult(0)
        XCTAssertTrue(model.canApply, "No-op when no save could have been attempted")
        model.configLoaded = true
        model.notice = ""
        model.handleSaveConfigResult(0)
        XCTAssertFalse(model.canApply)
        XCTAssertTrue(model.notice.contains("重新掃描"))
    }

    @MainActor func testLatePreviewCallbacksCannotRestoreValidityAfterSave() throws {
        let model = AppModel()
        model.navigate(to: Page.clean)
        try self.successfulPreview(model)
        model.configLoaded = true
        model.handleSaveConfigResult(0)
        // A late clean_preview completion (e.g. a delayed completion handler)
        // must not re-stamp the expired preview.
        model.finishCleanPreview(exitCode: 0)
        XCTAssertFalse(model.canApply, "Late finish callback cannot restore expired validity")
        // With no config loaded (no save in flight), the result handler must be
        // a strict no-op: generation token unchanged.
        model.configLoaded = false
        let generation = model.previewGeneration
        model.handleSaveConfigResult(0)
        XCTAssertEqual(model.previewGeneration, generation)
    }

    @MainActor func testStaleSaveCompletionIsDiscardedWhenGenerationAdvanced() throws {
        let model = AppModel()
        model.navigate(to: Page.clean)
        try self.successfulPreview(model)
        model.configLoaded = true
        // A newer preview beginning advances the token, so an in-flight save's
        // captured token no longer matches and its completion is discarded.
        let staleGeneration = model.previewGeneration
        model.beginCleanPreview()
        XCTAssertNotEqual(model.previewGeneration, staleGeneration)
        model.handleSaveCompletion(capturedGeneration: staleGeneration, rc: 0)
        XCTAssertFalse(model.cleanPreview.isInvalid, "Stale save result must not invalidate the fresh preview")
        XCTAssertTrue(model.notice.isEmpty, "Stale save result must not post a notice")
        // The current in-flight save still applies on completion.
        model.handleSaveCompletion(capturedGeneration: model.previewGeneration, rc: 1)
        XCTAssertTrue(model.cleanPreview.isInvalid, "Current-generation failed save must fail closed")
    }

    @MainActor func testDisclosureStringsMentionPreviewSideEffects() {
        let model = AppModel()
        model.navigate(to: Page.clean)
        XCTAssertTrue(model.actionInstructions.contains("預覽檔"), "Dry-run writes must be disclosed: \(model.actionInstructions)")
        XCTAssertTrue(model.actionInstructions.contains("暫存"))
        XCTAssertTrue(model.actionInstructions.contains("重新掃描"))
        XCTAssertTrue(model.actionInstructions.contains("日誌"))
        model.runner.taskTitle = "分析可清理項目"
        XCTAssertTrue(model.progressMessage.contains("暫存"), "Progress copy must also disclose side effects")
        XCTAssertFalse(model.progressMessage.contains("只讀取"), "Preview progress must not claim read-only")
    }
}
