import Foundation
import CoreFoundation

public enum StatusMetric: CaseIterable {
    case cpu, memory, rx, tx
}

/// Values reported by metrics.go; unknown fields remain nil, never invented zeros.
public struct StatusSample: Equatable {
    public let timestamp: Date
    public let cpu: Double?
    public let memory: Double?
    public let rx: Double?
    public let tx: Double?

    public init?(snapshot: [String: Any]) {
        guard let text = snapshot["collected_at"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: text)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: text)
        }
        guard let date = date, date.timeIntervalSince1970.isFinite else { return nil }
        timestamp = date
        cpu = Self.reading((snapshot["cpu"] as? [String: Any])?["usage"], percent: true)
        memory = Self.reading((snapshot["memory"] as? [String: Any])?["used_percent"], percent: true)
        let network = snapshot["network"] as? [[String: Any]]
        rx = Self.total(network, key: "rx_rate_mbs")
        tx = Self.total(network, key: "tx_rate_mbs")
    }

    public func value(for metric: StatusMetric) -> Double? {
        switch metric {
        case .cpu: return cpu
        case .memory: return memory
        case .rx: return rx
        case .tx: return tx
        }
    }

    private static func reading(_ raw: Any?, percent: Bool = false) -> Double? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, !percent || value <= 100 else { return nil }
        return value
    }

    // Each direction is unknown if ANY reported interface lacks a valid reading.
    // This is the sum of reported interfaces, not system-wide unique traffic.
    private static func total(_ network: [[String: Any]]?, key: String) -> Double? {
        guard let network = network, !network.isEmpty else { return nil }
        var total = 0.0
        for interface in network {
            guard let value = reading(interface[key]) else { return nil }
            total += value
            guard total.isFinite else { return nil }
        }
        return total
    }
}

/// Normalized plot coordinates: x=0 is now-60s, x=1 is now, y=0 is the top.
public struct StatusPlotPoint: Equatable {
    public let x: Double
    public let y: Double
}

/// Pure, bounded timestamp history. No timers, I/O or producer-side history arrays.
public struct StatusHistory {
    public static let window: TimeInterval = 60
    public static let freshness: TimeInterval = 10
    public static let maximumGap: TimeInterval = 6
    public let pointCap: Int
    public private(set) var samples: [StatusSample] = []
    // Retain the actual last update after points age out; also an ordering watermark.
    public private(set) var latestTimestamp: Date?

    public init(pointCap: Int = 120) { self.pointCap = max(1, pointCap) }

    @discardableResult public mutating func ingest(_ snapshot: [String: Any], now: Date) -> Bool {
        guard now.timeIntervalSince1970.isFinite else { return false }
        samples = visibleSamples(now: now)
        guard let sample = StatusSample(snapshot: snapshot) else { return false }
        let age = now.timeIntervalSince(sample.timestamp)
        guard age >= 0, age <= Self.window,
              latestTimestamp.map({ sample.timestamp > $0 }) ?? true else { return false }
        samples.append(sample)
        if samples.count > pointCap { samples.removeFirst(samples.count - pointCap) }
        latestTimestamp = sample.timestamp
        return true
    }

    public func visibleSamples(now: Date) -> [StatusSample] {
        samples.filter {
            let age = now.timeIntervalSince($0.timestamp)
            return age >= 0 && age <= Self.window
        }
    }

    public func isFresh(now: Date) -> Bool {
        guard let timestamp = latestTimestamp else { return false }
        let age = now.timeIntervalSince(timestamp)
        return age >= 0 && age <= Self.freshness
    }

    public func networkUpperBound(now: Date) -> Double {
        max(1, visibleSamples(now: now).flatMap { [$0.rx, $0.tx].compactMap { $0 } }.max() ?? 0)
    }

    /// Missing readings and >6s gaps start new subpaths; never interpolate across them.
    public func segments(for metric: StatusMetric, now: Date, upperBound: Double) -> [[StatusPlotPoint]] {
        guard upperBound.isFinite, upperBound > 0 else { return [] }
        var result: [[StatusPlotPoint]] = []
        var previous: Date?
        for sample in visibleSamples(now: now) {
            guard let value = sample.value(for: metric) else { previous = nil; continue }
            let point = StatusPlotPoint(
                x: 1 - now.timeIntervalSince(sample.timestamp) / Self.window,
                y: 1 - min(1, value / upperBound))
            if let previous = previous, sample.timestamp.timeIntervalSince(previous) <= Self.maximumGap {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
            previous = sample.timestamp
        }
        return result
    }
}
