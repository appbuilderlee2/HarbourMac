import XCTest
@testable import HarbourCore

final class HistorySummaryTests: XCTestCase {
    // All records in this suite are synthetic; no personal history is read.
    private func object(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
    private func summary(_ rows: [[String: Any]]) -> HistorySummary {
        HistorySummary(["limit": 20, "sessions": [], "deletions": rows])
    }
    private func deletion(_ status: String = "ok", mode: String = "permanent", size: Any = 2) -> [String: Any] {
        ["timestamp": "2026-09-01T12:00:00+0800", "mode": mode, "status": status,
         "size_kb": size, "path": "/synthetic/cache"]
    }

    func testBundledProducerWithIsolatedSyntheticLogs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let parser = root.appendingPathComponent("Sources/HarbourMac/Resources/Engine/lib/core/history.sh")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let operations = temp.appendingPathComponent("operations.log")
        let deletions = temp.appendingPathComponent("deletions.log")
        // Formats from log.sh session markers/get_timestamp and file_ops.sh _mole_delete_log.
        try """
        # ========== clean session started at 2026-08-31 23:59:00 ==========
        [2026-08-31 23:59:01] [clean] REMOVED /synthetic/cache (2KB)
        [2026-08-31 23:59:02] [clean] SKIPPED /synthetic/kept
        # ========== clean session ended at 2026-09-01 00:00:00, 1 items, 2.00KB ==========
        # ========== optimize session started at 2026-09-01 00:01:00 ==========
        [2026-09-01 00:01:01] [optimize] TASK_FAILED synthetic-task
        """.write(to: operations, atomically: true, encoding: .utf8)
        try "2026-09-01T00:00:00+0800\tpermanent\t2\tok\t/synthetic/cache\n2026-09-01T00:01:00+0800\ttrash\tunknown\tok\t/synthetic/app\n"
            .write(to: deletions, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Skip base utility initialization; call only the inspected parser/JSON
        // renderer, never mole, cleanup entry points, or the real user's logs.
        process.arguments = ["-c", "source \"$1\"; history_load_operations \"$2\"; history_load_deletions \"$3\"; history_render_json 2",
                             "synthetic-history-test", parser.path, operations.path, deletions.path]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": temp.path, "MOLE_BASE_LOADED": "1",
                               "MOLE_OPERATIONS_LOG": operations.path, "MOLE_DELETE_LOG": deletions.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(raw.keys), Set(["logs", "limit", "sessions", "deletions"]))
        let result = HistorySummary(raw)
        XCTAssertEqual(result.sessions.map(\.command), ["optimize", "clean"])
        XCTAssertEqual(result.cleanSessionCount, 1)
        XCTAssertEqual(result.optimizeSessionCount, 1)
        guard result.sessions.count == 2, result.deletions.count == 2 else {
            XCTFail("Expected two synthetic sessions and deletion records")
            return
        }
        XCTAssertNil(result.sessions[0].endedAt)
        XCTAssertEqual(result.sessions[0].failedTasks, 1)
        XCTAssertEqual(result.sessions[1].startedAt, "2026-08-31 23:59:00")
        XCTAssertEqual(result.sessions[1].endedAt, "2026-09-01 00:00:00")
        XCTAssertEqual(result.sessions[1].actions.removed, 1)
        XCTAssertEqual(result.sessions[1].actions.skipped, 1)
        XCTAssertEqual(result.sessions[1].items, 1)
        XCTAssertEqual(result.sessions[1].operationCount, 2)
        XCTAssertEqual(result.sessions[1].reportedSize, "2.00KB")
        XCTAssertNil(result.deletions[0].sizeKB)
        XCTAssertEqual(result.deletions[0].timestamp, "2026-09-01T00:01:00+0800")
        XCTAssertEqual(result.count(.trashOK), 1)
        XCTAssertEqual(result.knownPermanentBytes, 2048)
        XCTAssertTrue(result.sessionLimitReached)
        XCTAssertTrue(result.deletionLimitReached)
    }

    func testOnlyPermanentOKSizesContributeAndSessionsAreNotAdded() {
        let rows = [deletion(), deletion(mode: "trash"), deletion("dry-run"), deletion("error"),
                    deletion("rejected"), deletion("ok", mode: "future-mode"), deletion("future-status")]
        let result = HistorySummary(["limit": 20, "sessions": [["command": "clean", "size": "1.00TB", "items": 999]], "deletions": rows])
        XCTAssertEqual(result.knownPermanentBytes, 2048)
        for outcome: HistoryDeletion.Outcome in [.permanentOK, .trashOK, .preview, .failed, .skipped] {
            XCTAssertEqual(result.count(outcome), 1)
        }
        XCTAssertEqual(result.count(.unknown), 2)
        XCTAssertFalse(result.deletionLimitReached)
    }

    func testEveryProducerStatusHasConservativeClassification() {
        for status in ["rejected", "mutable-parent", "identity-changed", "privacy-denied", "sudo-blocked-test-mode"] {
            XCTAssertEqual(HistoryDeletion(deletion(status)).outcome, .skipped, status)
        }
        for status in ["invalid-mode", "trash-failed", "error", "timed-out", "interrupted"] {
            XCTAssertEqual(HistoryDeletion(deletion(status)).outcome, .failed, status)
        }
        for status in ["OK", "deleted", "success", "", "future"] {
            XCTAssertEqual(HistoryDeletion(deletion(status)).outcome, .unknown, status)
        }
    }

    func testUnknownZeroAndMalformedNumbersRemainDistinct() throws {
        let raw = try object("""
        {"limit":20,"sessions":[],"deletions":[
          {"mode":"permanent","status":"ok","size_kb":null},
          {"mode":"permanent","status":"ok"},
          {"mode":"permanent","status":"ok","size_kb":0}
        ]}
        """)
        let result = HistorySummary(raw)
        XCTAssertEqual(result.knownPermanentBytes, 0)
        XCTAssertEqual(result.unknownPermanentSizeCount, 2)
        XCTAssertEqual(result.deletions.last?.sizeKB, 0)
        for value: Any in [true, false, "123", "unknown", -1, 1.25, NSNull(), Double.infinity, Double.nan, UInt64.max] {
            XCTAssertNil(HistoryDeletion(deletion(size: value)).sizeKB, "\(value)")
            XCTAssertNil(HistorySession(["items": value]).items)
        }
    }

    func testOverflowDoesNotWrapOrReturnPartialTotal() {
        let maximumKB = Int64.max / 1024
        XCTAssertEqual(summary([deletion(size: maximumKB)]).knownPermanentBytes, maximumKB * 1024)
        for rows in [[deletion(size: maximumKB + 1)], [deletion(size: maximumKB), deletion(size: 1)]] {
            let result = summary(rows)
            XCTAssertTrue(result.permanentSizeOverflow)
            XCTAssertNil(result.knownPermanentBytes)
        }
    }

    func testAbsentMalformedCollectionsAndSessionFields() {
        XCTAssertTrue(HistorySummary([:]).hasInvalidCollections)
        let empty = HistorySummary(["sessions": [], "deletions": [], "limit": 20])
        XCTAssertFalse(empty.hasInvalidCollections)
        XCTAssertEqual(empty.sessions.count, 0)
        let partial = HistorySummary(["sessions": [NSNull(), ["command": "clean"]], "deletions": "bad"])
        XCTAssertTrue(partial.hasInvalidCollections)
        XCTAssertEqual(partial.invalidRowCount, 1)
        XCTAssertEqual(partial.cleanSessionCount, 1)
        XCTAssertNil(partial.sessions[0].actions.failed)
        let malformed = HistorySession(["command": true, "started_at": NSNull(), "ended_at": "", "size": 42,
                                        "actions": ["removed": -1, "failed": false], "failed_tasks": "1"])
        XCTAssertNil(malformed.command)
        XCTAssertNil(malformed.startedAt)
        XCTAssertNil(malformed.endedAt)
        XCTAssertNil(malformed.reportedSize)
        XCTAssertNil(malformed.actions.removed)
        XCTAssertNil(malformed.actions.failed)
        XCTAssertNil(malformed.failedTasks)
        for limit: Any in [0, 201, -1, "20", true, NSNull()] {
            XCTAssertNil(HistorySummary(["limit": limit]).limit)
        }
    }
}
