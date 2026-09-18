/// A measured child of an analyzed directory. No filesystem access occurs here.
public struct TreemapItem: Equatable {
    public let path: String
    public let size: Int64

    public init(path: String, size: Int64) {
        self.path = path
        self.size = size
    }
}

public struct TreemapFrame: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct TreemapNode: Identifiable, Equatable {
    // A separate case prevents a real path from colliding with the aggregate ID.
    public enum ID: Hashable {
        case path(String)
        case other
    }
    public let id: ID
    public let items: [TreemapItem]
    /// Double addition avoids Int64 overflow; it is for area, not exact byte totals.
    public var size: Double { items.reduce(0.0) { $0 + Double($1.size) } }
}

public struct TreemapTile: Identifiable, Equatable {
    public var id: TreemapNode.ID { node.id }
    public let node: TreemapNode
    public let frame: TreemapFrame
}

/// Deterministic, bounded-cost binary treemap for returned positive-sized entries.
/// The map normalizes to these entries only, never to volume capacity or a recursive
/// large-file list. No minimum tile area is imposed: subpixel entries remain in the
/// node membership/list even when floating-point rounding makes them invisible.
public struct DiskTreemap {
    public static let maximumTiles = 256
    public let nodes: [TreemapNode]
    public var totalSize: Double { nodes.reduce(0.0) { $0 + $1.size } }

    public init(items: [TreemapItem]) {
        // Paths are identity. Malformed repeated readings must not double count;
        // choosing the largest positive reading is independent of arrival order.
        var byPath: [String: Int64] = [:]
        for item in items where item.size > 0 {
            byPath[item.path] = max(byPath[item.path] ?? 0, item.size)
        }
        let sorted = byPath.map { TreemapItem(path: $0.key, size: $0.value) }.sorted {
            $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size
        }
        if sorted.count > Self.maximumTiles {
            let directCount = Self.maximumTiles - 1
            nodes = sorted.prefix(directCount).map { TreemapNode(id: .path($0.path), items: [$0]) }
                + [TreemapNode(id: .other, items: Array(sorted.dropFirst(directCount)))]
        } else {
            nodes = sorted.map { TreemapNode(id: .path($0.path), items: [$0]) }
        }
    }

    public func layout(in bounds: TreemapFrame) -> [TreemapTile] {
        let area = bounds.width * bounds.height
        guard !nodes.isEmpty,
              [bounds.x, bounds.y, bounds.width, bounds.height,
               bounds.x + bounds.width, bounds.y + bounds.height, area].allSatisfy(\.isFinite),
              bounds.width > 0, bounds.height > 0, area > 0 else { return [] }
        let weights = nodes.map(\.size)
        var tiles: [TreemapTile] = []
        tiles.reserveCapacity(nodes.count)

        func split(_ range: Range<Int>, _ frame: TreemapFrame) {
            guard range.count > 1 else {
                tiles.append(TreemapTile(node: nodes[range.lowerBound], frame: frame))
                return
            }
            let total = range.reduce(0.0) { $0 + weights[$1] }
            var prefix = 0.0
            var cut = range.lowerBound + 1
            var bestDistance = Double.infinity
            // Keep contiguous order and split as close to half the weight as possible.
            for index in range.dropLast() {
                prefix += weights[index]
                let distance = abs(total / 2 - prefix)
                if distance < bestDistance {
                    bestDistance = distance
                    cut = index + 1
                }
            }
            let left = range.lowerBound..<cut
            let right = cut..<range.upperBound
            // Sum each side independently: subtraction would erase tiny readings.
            let leftWeight = left.reduce(0.0) { $0 + weights[$1] }
            let rightWeight = right.reduce(0.0) { $0 + weights[$1] }
            let fraction = min(1, max(0, leftWeight / (leftWeight + rightWeight)))
            if frame.width >= frame.height {
                let width = frame.width * fraction
                split(left, TreemapFrame(x: frame.x, y: frame.y, width: width, height: frame.height))
                split(right, TreemapFrame(x: frame.x + width, y: frame.y,
                                         width: max(0, frame.width - width), height: frame.height))
            } else {
                let height = frame.height * fraction
                split(left, TreemapFrame(x: frame.x, y: frame.y, width: frame.width, height: height))
                split(right, TreemapFrame(x: frame.x, y: frame.y + height,
                                         width: frame.width, height: max(0, frame.height - height)))
            }
        }
        split(nodes.indices, bounds)
        return tiles
    }
}
