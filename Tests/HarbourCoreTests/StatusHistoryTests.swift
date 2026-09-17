import XCTest
@testable import HarbourCore

final class StatusHistoryTests: XCTestCase {
    // Synthetic fixtures mirror metrics.go, not recordings from a real machine.
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture(_ offset: TimeInterval = 0) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ["collected_at": formatter.string(from: epoch.addingTimeInterval(offset)),
                "cpu": ["usage": 25.0], "memory": ["used_percent": 50.0],
                "network": [["name": "en0", "rx_rate_mbs": 1.5, "tx_rate_mbs": 0.0],
                            ["name": "en1", "rx_rate_mbs": 2.5, "tx_rate_mbs": 0.5]]]
    }

    func testProducerSchemaAndStrictUnknownVersusZero() throws {
        let sample = try XCTUnwrap(StatusSample(snapshot: fixture()))
        XCTAssertEqual(sample.cpu, 25)
        XCTAssertEqual(sample.memory, 50)
        XCTAssertEqual(sample.rx, 4)
        XCTAssertEqual(sample.tx, 0.5)
        XCTAssertEqual(sample.timestamp, epoch)
        for invalid in [true, false, "20", NSNull(), -1.0, 101.0, Double.nan, Double.infinity] as [Any] {
            var value = fixture()
            value["cpu"] = ["usage": invalid]
            value["memory"] = ["used_percent": invalid]
            let parsed = try XCTUnwrap(StatusSample(snapshot: value))
            XCTAssertNil(parsed.cpu)
            XCTAssertNil(parsed.memory)
        }
        var zero = fixture()
        zero["cpu"] = ["usage": 0]
        zero["memory"] = ["used_percent": 100]
        XCTAssertEqual(StatusSample(snapshot: zero)?.cpu, 0)
        XCTAssertEqual(StatusSample(snapshot: zero)?.memory, 100)
        zero.removeValue(forKey: "cpu")
        XCTAssertNil(StatusSample(snapshot: zero)?.cpu)
    }

    func testNetworkRequiresEveryReportedInterfaceForEachDirection() throws {
        for invalid in [true, "0", NSNull(), -1.0, Double.nan, Double.infinity] as [Any] {
            var value = fixture()
            value["network"] = [["rx_rate_mbs": 1, "tx_rate_mbs": 0],
                                ["rx_rate_mbs": invalid, "tx_rate_mbs": 2]]
            let sample = try XCTUnwrap(StatusSample(snapshot: value))
            XCTAssertNil(sample.rx, "Do not show a partial total")
            XCTAssertEqual(sample.tx, 2)
        }
        for network in [NSNull(), [], "bad", [["rx_rate_mbs": 1]], [["rx_rate_mbs": 1], "bad"]] as [Any] {
            var value = fixture(); value["network"] = network
            XCTAssertNil(StatusSample(snapshot: value)?.tx)
        }
        var value = fixture()
        value["network"] = [["rx_rate_mbs": Double.greatestFiniteMagnitude],
                            ["rx_rate_mbs": Double.greatestFiniteMagnitude]]
        XCTAssertNil(StatusSample(snapshot: value)?.rx)
        value.removeValue(forKey: "network")
        XCTAssertNil(StatusSample(snapshot: value)?.rx)
    }

    func testTimestampFormatsAndInvalidTimestampRejection() {
        var value = fixture()
        for timestamp in [true, 1_800_000_000, "", "2027-01-15", "invalid", NSNull()] as [Any] {
            value["collected_at"] = timestamp
            XCTAssertNil(StatusSample(snapshot: value))
        }
        for text in ["2027-01-15T08:00:00Z", "2027-01-15T08:00:00.123456789Z", "2027-01-15T16:00:00+08:00"] {
            value["collected_at"] = text
            XCTAssertNotNil(StatusSample(snapshot: value))
        }
        value.removeValue(forKey: "collected_at")
        XCTAssertNil(StatusSample(snapshot: value))
    }

    func testSixtySecondInclusiveBoundaryAndPointCapAreIndependent() {
        var history = StatusHistory(pointCap: 100)
        for second in 0...61 {
            XCTAssertTrue(history.ingest(fixture(Double(second)), now: epoch.addingTimeInterval(Double(second))))
        }
        XCTAssertEqual(history.samples.count, 61)
        XCTAssertEqual(history.samples.first?.timestamp, epoch.addingTimeInterval(1))
        XCTAssertEqual(history.visibleSamples(now: epoch.addingTimeInterval(61.001)).count, 60)
        XCTAssertTrue(history.visibleSamples(now: epoch.addingTimeInterval(122)).isEmpty)
        var capped = StatusHistory(pointCap: 3)
        for second in 0...10 { _ = capped.ingest(fixture(Double(second)), now: epoch.addingTimeInterval(Double(second))) }
        XCTAssertEqual(capped.samples.count, 3)
        XCTAssertEqual(capped.samples.first?.timestamp, epoch.addingTimeInterval(8))
        XCTAssertEqual(StatusHistory(pointCap: 0).pointCap, 1)
    }

    func testOrderingFutureStaleAndFreshnessUseInjectedNow() {
        var history = StatusHistory()
        XCTAssertTrue(history.ingest(fixture(), now: epoch))
        XCTAssertFalse(history.ingest(fixture(), now: epoch))
        XCTAssertFalse(history.ingest(fixture(-1), now: epoch))
        XCTAssertFalse(history.ingest(fixture(1), now: epoch))
        XCTAssertFalse(history.ingest(fixture(-61), now: epoch))
        XCTAssertEqual(history.latestTimestamp, epoch)
        XCTAssertTrue(history.isFresh(now: epoch.addingTimeInterval(10)))
        XCTAssertFalse(history.isFresh(now: epoch.addingTimeInterval(10.001)))
        XCTAssertFalse(history.isFresh(now: epoch.addingTimeInterval(-1)))
        XCTAssertFalse(history.ingest(fixture(), now: epoch.addingTimeInterval(100)))
        XCTAssertTrue(history.samples.isEmpty, "Prune even on rejected input")
        XCTAssertEqual(history.latestTimestamp, epoch, "Keep the actual last update, not receipt time")
        var delayed = StatusHistory()
        XCTAssertTrue(delayed.ingest(fixture(), now: epoch.addingTimeInterval(60)))
        XCTAssertFalse(delayed.isFresh(now: epoch.addingTimeInterval(60)))
    }

    func testCoordinatesUseTimeAndBreakMissingAndLongGaps() throws {
        var history = StatusHistory()
        for second in [0.0, 2, 4, 6, 20] {
            var value = fixture(second)
            if second == 4 { value["cpu"] = [:] }
            XCTAssertTrue(history.ingest(value, now: epoch.addingTimeInterval(second)))
        }
        let segments = history.segments(for: .cpu, now: epoch.addingTimeInterval(60), upperBound: 100)
        XCTAssertEqual(segments.map(\.count), [2, 1, 1])
        let first = try XCTUnwrap(segments.first?.first)
        XCTAssertEqual(first.x, 0, accuracy: 0.0001)
        XCTAssertEqual(first.y, 0.75, accuracy: 0.0001)
        XCTAssertEqual(segments[0][1].x, 2.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(segments[2][0].x, 20.0 / 60, accuracy: 0.0001)
        XCTAssertTrue(history.segments(for: .cpu, now: epoch.addingTimeInterval(81), upperBound: 100).isEmpty)
        XCTAssertTrue(history.segments(for: .cpu, now: epoch, upperBound: 0).isEmpty)
        XCTAssertTrue(history.segments(for: .cpu, now: epoch, upperBound: .nan).isEmpty)
    }

    func testNoSamplesSinglePointFlatZeroAndNetworkScale() {
        var history = StatusHistory()
        XCTAssertTrue(history.segments(for: .cpu, now: epoch, upperBound: 100).isEmpty)
        XCTAssertNil(history.latestTimestamp)
        XCTAssertFalse(history.isFresh(now: epoch))
        var value = fixture(); value["cpu"] = ["usage": 0]
        _ = history.ingest(value, now: epoch)
        let points = history.segments(for: .cpu, now: epoch, upperBound: 100)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].count, 1)
        XCTAssertEqual(points[0][0].x, 1)
        XCTAssertEqual(points[0][0].y, 1)
        XCTAssertEqual(history.networkUpperBound(now: epoch), 4)
        value = fixture(2); value["cpu"] = ["usage": 0]
        _ = history.ingest(value, now: epoch.addingTimeInterval(2))
        XCTAssertEqual(history.segments(for: .cpu, now: epoch.addingTimeInterval(2), upperBound: 100)[0].map(\.y), [1, 1])
    }
}
