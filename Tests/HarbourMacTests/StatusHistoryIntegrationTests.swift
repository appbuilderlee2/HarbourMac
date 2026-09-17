import XCTest
import HarbourCore
@testable import HarbourMac

final class StatusHistoryIntegrationTests: XCTestCase {
    // Explicit synthetic metrics.go schema. The injected starter never launches Runner.
    private let data = Data(#"{"collected_at":"2027-01-15T08:00:00Z","cpu":{"usage":20},"memory":{"used_percent":40},"network":[{"name":"en0","rx_rate_mbs":0,"tx_rate_mbs":2}]}"#.utf8)
    private var now: Date { ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z")! }

    func testSnapshotAndStreamUseSameIngestionWithoutEngine() async throws {
        try await MainActor.run {
            let snapshot = AppModel(), stream = AppModel()
            snapshot.loadStatus(live: false, now: { self.now }, start: { completion in completion(self.data, 0) })
            var finish: ((Data, Int32) -> Void)?
            stream.loadStatus(live: true, now: { self.now }, start: { finish = $0 })
            stream.runner.onLine?(String(decoding: self.data, as: UTF8.self))
            XCTAssertEqual(snapshot.statusHistory.samples, stream.statusHistory.samples)
            XCTAssertEqual(snapshot.statusHistory.samples.count, 1)
            XCTAssertEqual(snapshot.statusHistory.samples.first?.rx, 0)
            XCTAssertEqual(snapshot.snapshot["collected_at"] as? String, stream.snapshot["collected_at"] as? String)
            XCTAssertFalse(snapshot.watch)
            XCTAssertTrue(stream.watch)
            let completion = try XCTUnwrap(finish)
            completion(Data(), 1)
            XCTAssertFalse(stream.watch)
            XCTAssertTrue(stream.statusReadFailed)
            XCTAssertEqual(stream.statusHistory.latestTimestamp, self.now)
            XCTAssertFalse(stream.runner.busy)
        }
    }

    func testResetBusyGuardAndStoppedStreamCannotIngestLateLines() async throws {
        try await MainActor.run {
            let model = AppModel()
            model.loadStatus(live: false, now: { self.now }, start: { $0(self.data, 0) })
            model.runner.busy = true
            model.loadStatus(live: true, start: { _ in XCTFail("Busy load must not start") })
            XCTAssertEqual(model.statusHistory.samples.count, 1)
            model.runner.busy = false
            var clock = self.now
            model.loadStatus(live: true, now: { clock }, start: { _ in })
            XCTAssertTrue(model.statusHistory.samples.isEmpty)
            XCTAssertTrue(model.snapshot.isEmpty)
            let line = try XCTUnwrap(model.runner.onLine)
            line(String(decoding: self.data, as: UTF8.self))
            XCTAssertEqual(model.statusHistory.samples.count, 1)
            model.cancel() // No process exists; exercises the real watch=false path.
            let later = String(decoding: self.data, as: UTF8.self).replacingOccurrences(of: "08:00:00", with: "08:00:02")
            clock = self.now.addingTimeInterval(2)
            line(later)
            XCTAssertFalse(model.watch)
            XCTAssertEqual(model.statusHistory.samples.count, 1)
            XCTAssertFalse(model.statusReadFailed, "Stopped callback must not enter ingestion")
            XCTAssertEqual(model.statusHistory.latestTimestamp, self.now)
        }
    }

    @MainActor func testDisplayNeverCallsStoppedFailedOrStaleDataLive() throws {
        var history = StatusHistory()
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        _ = history.ingest(value, now: now)
        XCTAssertTrue(StatusTrendsView.stateText(history: history, monitoring: false, failed: false, now: now).contains("已停止"))
        XCTAssertTrue(StatusTrendsView.stateText(history: history, monitoring: true, failed: true, now: now).contains("不是即時"))
        XCTAssertTrue(StatusTrendsView.stateText(history: history, monitoring: true, failed: false, now: now.addingTimeInterval(11)).contains("已過時"))
        XCTAssertTrue(StatusTrendsView.stateText(history: StatusHistory(), monitoring: true, failed: false, now: now).contains("等待第一份"))
    }

    func testRunnerGateCannotDeliverOldOrCompletedStatusLines() async {
        await MainActor.run {
            let model = AppModel()
            model.loadStatus(live: true, now: { self.now }, start: { _ in })
            model.runner.busy = true
            let current = model.runner.runID
            let line = String(decoding: self.data, as: UTF8.self)
            model.runner.receive(for: UUID()) { $0.onLine?(line) }
            XCTAssertTrue(model.statusHistory.samples.isEmpty)
            model.runner.receive(for: current) { $0.onLine?(line) }
            XCTAssertEqual(model.statusHistory.samples.count, 1)
            model.runner.busy = false
            model.runner.receive(for: current) { $0.onLine?("bad") }
            XCTAssertFalse(model.statusReadFailed)
        }
    }

    func testInvalidAndFutureDataNeverRefreshLatestAndNewRequestClearsFailure() async {
        await MainActor.run {
            let model = AppModel()
            model.loadStatus(live: true, now: { self.now }, start: { _ in })
            model.runner.onLine?(String(decoding: self.data, as: UTF8.self))
            model.runner.onLine?("not JSON")
            XCTAssertTrue(model.statusReadFailed)
            XCTAssertEqual(model.statusHistory.latestTimestamp, self.now)
            let future = String(decoding: self.data, as: UTF8.self).replacingOccurrences(of: "08:00:00", with: "08:00:02")
            model.runner.onLine?(future)
            XCTAssertTrue(model.statusReadFailed)
            XCTAssertEqual(model.statusHistory.samples.count, 1)
            model.loadStatus(live: false, now: { self.now }, start: { $0(self.data, 0) })
            XCTAssertFalse(model.statusReadFailed)
            XCTAssertEqual(model.statusHistory.samples.count, 1)
            model.loadStatus(live: false, start: { $0(Data(), 127) })
            XCTAssertTrue(model.statusReadFailed)
            XCTAssertTrue(model.snapshot.isEmpty)
            XCTAssertNil(model.statusHistory.latestTimestamp)
        }
    }
}
