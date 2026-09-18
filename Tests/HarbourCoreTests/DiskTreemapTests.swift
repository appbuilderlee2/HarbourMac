import XCTest
@testable import HarbourCore

final class DiskTreemapTests: XCTestCase {
    // All values/paths in this suite are synthetic test fixtures.
    private func item(_ path: String, _ size: Int64) -> TreemapItem {
        TreemapItem(path: path, size: size)
    }
    private let bounds = TreemapFrame(x: 0, y: 0, width: 800, height: 300)

    private func verify(_ tiles: [TreemapTile], in bounds: TreemapFrame,
                        file: StaticString = #filePath, line: UInt = #line) {
        let area = bounds.width * bounds.height
        let totalWeight = tiles.reduce(0.0) { $0 + $1.node.size }
        XCTAssertEqual(tiles.reduce(0.0) { $0 + $1.frame.width * $1.frame.height }, area,
                       accuracy: area * 1e-10, file: file, line: line)
        for (index, tile) in tiles.enumerated() {
            let r = tile.frame
            XCTAssertTrue([r.x, r.y, r.width, r.height].allSatisfy(\.isFinite), file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.width, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.height, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.x, bounds.x, file: file, line: line)
            XCTAssertGreaterThanOrEqual(r.y, bounds.y, file: file, line: line)
            XCTAssertLessThanOrEqual(r.x + r.width, bounds.x + bounds.width + 1e-9, file: file, line: line)
            XCTAssertLessThanOrEqual(r.y + r.height, bounds.y + bounds.height + 1e-9, file: file, line: line)
            XCTAssertEqual(r.width * r.height / area, tile.node.size / totalWeight,
                           accuracy: 1e-10, file: file, line: line)
            for other in tiles.dropFirst(index + 1) {
                let s = other.frame
                let overlapWidth = min(r.x + r.width, s.x + s.width) - max(r.x, s.x)
                let overlapHeight = min(r.y + r.height, s.y + s.height) - max(r.y, s.y)
                XCTAssertTrue(overlapWidth <= 1e-9 || overlapHeight <= 1e-9, file: file, line: line)
            }
        }
    }

    func testEmptyZerosAndNegativeValues() {
        for items in [[], [item("zero", 0), item("negative", -1), item("min", .min)]] {
            XCTAssertTrue(DiskTreemap(items: items).layout(in: bounds).isEmpty)
        }
        let map = DiskTreemap(items: [item("a", 0), item("b", 30), item("c", -2)])
        XCTAssertEqual(map.nodes.count, 1)
        XCTAssertEqual(map.layout(in: bounds).first?.frame, bounds)
    }

    func testGeometryRatiosAndResizing() {
        let map = DiskTreemap(items: [item("a", 6), item("b", 3), item("c", 1)])
        for frame in [bounds, TreemapFrame(x: 10, y: -20, width: 70, height: 900),
                      TreemapFrame(x: 0, y: 0, width: 0.01, height: 0.02)] {
            verify(map.layout(in: frame), in: frame)
        }
    }

    func testInvalidBounds() {
        let map = DiskTreemap(items: [item("a", 1)])
        for frame in [TreemapFrame(x: 0, y: 0, width: 0, height: 10),
                      TreemapFrame(x: 0, y: 0, width: 10, height: -1),
                      TreemapFrame(x: .nan, y: 0, width: 10, height: 10),
                      TreemapFrame(x: 0, y: .infinity, width: 10, height: 10),
                      TreemapFrame(x: 0, y: 0, width: .infinity, height: 10),
                      TreemapFrame(x: 0, y: 0, width: .nan, height: 10),
                      TreemapFrame(x: 0, y: 0, width: .greatestFiniteMagnitude, height: 10),
                      TreemapFrame(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 1)] {
            XCTAssertTrue(map.layout(in: frame).isEmpty)
        }
    }

    func testInt64ExtremesAndTinyEntriesDoNotOverflowOrInflate() {
        let map = DiskTreemap(items: [item("a", .max), item("b", .max), item("tiny", 1),
                                     item("negative", .min)])
        XCTAssertTrue(map.totalSize.isFinite)
        XCTAssertGreaterThan(map.totalSize, Double(Int64.max))
        XCTAssertEqual(map.nodes.count, 3)
        verify(map.layout(in: bounds), in: bounds)
    }

    func testManyItemsHaveExplicitConservingOtherAggregate() {
        let items = (1...10_000).map { item("/fixture/\($0)", Int64($0)) }
        let map = DiskTreemap(items: items)
        XCTAssertEqual(map.nodes.count, DiskTreemap.maximumTiles)
        XCTAssertEqual(map.nodes.last?.id, .other)
        XCTAssertEqual(map.nodes.flatMap(\.items).count, items.count)
        XCTAssertEqual(Set(map.nodes.flatMap(\.items).map(\.path)).count, items.count)
        XCTAssertEqual(map.totalSize, 50_005_000)
        XCTAssertEqual(map.nodes.reduce(0) { $0 + $1.size }, map.totalSize)
        verify(map.layout(in: bounds), in: bounds)
    }

    func testDeterministicOrderAndDuplicatePaths() {
        let items = [item("z", 10), item("a", 10), item("c", 1), item("a", 2)]
        let map = DiskTreemap(items: items)
        XCTAssertEqual(map.nodes.map(\.id), [.path("a"), .path("z"), .path("c")])
        XCTAssertEqual(map.totalSize, 21, "Duplicate paths retain the largest reading, not a double count")
        XCTAssertEqual(map.layout(in: bounds), DiskTreemap(items: Array(items.reversed())).layout(in: bounds))
        let many = (1...400).map { item("fixture-\($0)", Int64($0 % 13 + 1)) }
        XCTAssertEqual(DiskTreemap(items: many).layout(in: bounds),
                       DiskTreemap(items: Array(many.reversed())).layout(in: bounds))
    }
}
