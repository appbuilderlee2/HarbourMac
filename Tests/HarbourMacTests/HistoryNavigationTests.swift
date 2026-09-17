import XCTest
@testable import HarbourMac

final class HistoryNavigationTests: XCTestCase {
    func testHistoryDestinationsOnlyNavigateWithoutStartingWork() async {
        await MainActor.run {
            let model = AppModel()
            for destination in [Page.clean, .optimize] {
                model.navigate(to: Page.history)
                let outcome = model.runner.outcome
                let log = model.runner.log
                model.navigate(to: destination)
                XCTAssertEqual(model.page, destination)
                XCTAssertFalse(model.runner.busy)
                XCTAssertEqual(model.runner.outcome, outcome)
                XCTAssertEqual(model.runner.log, log)
                XCTAssertFalse(model.canApply, "Revisit must not grant a preview")
                XCTAssertNil(model.confirm)
                XCTAssertFalse(model.selecting)
            }
        }
    }

    func testHistoryRevisitRespectsAllNavigationGuards() async {
        await MainActor.run {
            let model = AppModel()
            model.navigate(to: Page.history)
            for state in 0..<3 {
                model.runner.busy = state == 0
                model.selecting = state == 1
                model.confirm = state == 2 ? "synthetic confirmation" : nil
                for destination in [Page.clean, .optimize] {
                    XCTAssertFalse(model.canNavigate)
                    model.navigate(to: destination)
                    XCTAssertEqual(model.page, .history)
                }
            }
            model.runner.busy = false
            model.selecting = false
            model.confirm = nil
        }
    }

    // Static wiring regression: model tests alone cannot prove which action the
    // SwiftUI buttons invoke. Keep this narrow and inspect the view on macOS too.
    func testHistoryButtonsAreGuardedNavigationOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/HarbourMac/DataViews.swift"))
        let view = try XCTUnwrap(source.components(separatedBy: "struct HistoryView: View {").last)
        XCTAssertTrue(view.contains("Button(\"前往清理\") { model.navigate(to: Page.clean) }.disabled(!model.canNavigate)"))
        XCTAssertTrue(view.contains("Button(\"前往系統維護\") { model.navigate(to: Page.optimize) }.disabled(!model.canNavigate)"))
        XCTAssertFalse(view.contains("runner.start"))
        XCTAssertFalse(view.contains("model.operate"))
        XCTAssertFalse(view.contains("model.bridge"))
        XCTAssertFalse(view.contains("trashFiles"))
        XCTAssertTrue(view.contains("目前載入紀錄"))
        XCTAssertFalse(view.contains("本月"))
    }
}
