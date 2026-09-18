import Foundation
import CoreFoundation

/// Parses the bundled status-go schema, never substituting absent readings with zero.
public struct HUDMetrics {
    public let cpu: Double?
    public let memory: Double?
    public let received: Double?
    public let sent: Double?
    public let collectedAt: Date?

    public init(_ value: [String: Any]) {
        func number(_ raw: Any?, percent: Bool = false) -> Double? {
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let d = n.doubleValue
            guard d.isFinite, d >= 0, !percent || d <= 100 else { return nil }
            return d
        }
        cpu = number((value["cpu"] as? [String: Any])?["usage"], percent: true)
        memory = number((value["memory"] as? [String: Any])?["used_percent"], percent: true)
        // Show aggregate interface traffic, not an inferred Internet throughput.
        let networks = value["network"] as? [[String: Any]]
        func sum(_ key: String) -> Double? {
            guard let rows = networks, !rows.isEmpty else { return nil }
            let values = rows.compactMap { number($0[key]) }
            guard values.count == rows.count else { return nil }
            let total = values.reduce(0, +)
            return total.isFinite ? total : nil
        }
        received = sum("rx_rate_mbs")
        sent = sum("tx_rate_mbs")
        let formatter = ISO8601DateFormatter()
        let stamp = value["collected_at"] as? String ?? ""
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: stamp) { collectedAt = date }
        else {
            formatter.formatOptions = [.withInternetDateTime]
            collectedAt = formatter.date(from: stamp)
        }
    }

    public func isFresh(at now: Date = Date(), maxAge: TimeInterval = 30) -> Bool {
        guard let date = collectedAt else { return false }
        let age = now.timeIntervalSince(date)
        return age >= -5 && age <= maxAge
    }
    public static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "—"
    }
    public static func rate(_ value: Double?) -> String {
        value.map { String(format: "%.2f MB/s", $0) } ?? "—"
    }
}
