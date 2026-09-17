import Foundation
import CoreFoundation

/// Projection of bundled Engine/lib/core/history.sh, not a lifetime/monthly ledger.
/// Sessions and deletion audits are independent, newest-first, limited arrays.
public struct HistorySummary {
    public let sessions: [HistorySession]
    public let deletions: [HistoryDeletion]
    public let limit: Int64?
    public let hasInvalidCollections: Bool
    public let invalidRowCount: Int
    public let sessionLimitReached: Bool
    public let deletionLimitReached: Bool

    public var cleanSessionCount: Int { sessions.filter { $0.command == "clean" }.count }
    public var optimizeSessionCount: Int { sessions.filter { $0.command == "optimize" }.count }
    public func count(_ outcome: HistoryDeletion.Outcome) -> Int {
        deletions.filter { $0.outcome == outcome }.count
    }

    /// Sum only the measured audit sizes of permanent/ok records. Never add the
    /// rounded session.size (which can overlap the audit). This is NOT freed space:
    /// sizes are measured before the call, records can overlap, and ok is a return
    /// status, not a disk-space measurement. Trash and previews contribute nothing.
    public let knownPermanentBytes: Int64?
    public let unknownPermanentSizeCount: Int
    public let permanentSizeOverflow: Bool

    public init(_ object: [String: Any]) {
        let sessionRows = object["sessions"] as? [Any]
        let deletionRows = object["deletions"] as? [Any]
        let sessionObjects = (sessionRows ?? []).compactMap { $0 as? [String: Any] }
        let deletionObjects = (deletionRows ?? []).compactMap { $0 as? [String: Any] }
        sessions = sessionObjects.map(HistorySession.init)
        deletions = deletionObjects.map(HistoryDeletion.init)
        hasInvalidCollections = sessionRows == nil || deletionRows == nil
        invalidRowCount = (sessionRows?.count ?? 0) - sessionObjects.count
            + (deletionRows?.count ?? 0) - deletionObjects.count
        let parsedLimit = historyInteger(object["limit"])
        limit = parsedLimit.flatMap { (1...200).contains($0) ? $0 : nil }
        sessionLimitReached = limit.map { Int64(sessionRows?.count ?? 0) >= $0 } ?? false
        deletionLimitReached = limit.map { Int64(deletionRows?.count ?? 0) >= $0 } ?? false

        var total: Int64 = 0
        var unknown = 0
        var overflow = false
        for deletion in deletions where deletion.outcome == .permanentOK {
            guard let size = deletion.sizeKB else { unknown += 1; continue }
            let product = size.multipliedReportingOverflow(by: 1024)
            guard !product.overflow else { overflow = true; continue }
            let sum = total.addingReportingOverflow(product.partialValue)
            if sum.overflow { overflow = true } else { total = sum.partialValue }
        }
        unknownPermanentSizeCount = unknown
        permanentSizeOverflow = overflow
        knownPermanentBytes = overflow ? nil : total
    }
}

public struct HistorySession {
    public let command: String?
    /// Producer uses local YYYY-MM-DD HH:mm:ss without a timezone. Keep the
    /// source text; do not invent UTC, a month filter, or sort unlike the producer.
    public let startedAt: String?
    public let endedAt: String?
    /// Human-formatted/rounded producer value, deliberately not parsed as bytes.
    public let reportedSize: String?
    public let items: Int64?
    public let operationCount: Int64?
    public let failedTasks: Int64?
    public let actions: Actions

    public struct Actions {
        public let removed: Int64?
        public let trashed: Int64?
        public let skipped: Int64?
        public let failed: Int64?
        public let rebuilt: Int64?
        public let other: Int64?

        fileprivate init(_ object: [String: Any]) {
            removed = historyInteger(object["removed"])
            trashed = historyInteger(object["trashed"])
            skipped = historyInteger(object["skipped"])
            failed = historyInteger(object["failed"])
            rebuilt = historyInteger(object["rebuilt"])
            other = historyInteger(object["other"])
        }
    }

    public init(_ object: [String: Any]) {
        command = historyText(object["command"])
        startedAt = historyText(object["started_at"])
        endedAt = historyText(object["ended_at"])
        reportedSize = historyText(object["size"])
        items = historyInteger(object["items"])
        operationCount = historyInteger(object["operation_count"])
        failedTasks = historyInteger(object["failed_tasks"])
        actions = Actions(object["actions"] as? [String: Any] ?? [:])
    }
}

public struct HistoryDeletion {
    public enum Outcome: Equatable {
        case permanentOK, trashOK, preview, skipped, failed, unknown
    }
    /// Unlike session dates this source text includes a numeric timezone offset.
    public let timestamp: String?
    public let mode: String?
    public let status: String?
    public let path: String?
    /// du -sk units: 1024 bytes, despite the JSON key's name. null is unknown.
    public let sizeKB: Int64?
    public let outcome: Outcome

    public init(_ object: [String: Any]) {
        timestamp = historyText(object["timestamp"])
        mode = historyText(object["mode"])
        status = historyText(object["status"])
        path = historyText(object["path"])
        sizeKB = historyInteger(object["size_kb"])
        switch status {
        case "ok":
            outcome = mode == "permanent" ? .permanentOK : (mode == "trash" ? .trashOK : .unknown)
        case "dry-run": outcome = .preview
        case "rejected", "mutable-parent", "identity-changed", "privacy-denied", "sudo-blocked-test-mode":
            outcome = .skipped
        case "invalid-mode", "trash-failed", "error", "timed-out", "interrupted": outcome = .failed
        default: outcome = .unknown
        }
    }
}

private func historyText(_ value: Any?) -> String? {
    guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
}

/// JSON numeric integers only: reject bool, strings, fractions, negatives and
/// values beyond Int64 instead of truncating/wrapping NSNumber.int64Value.
private func historyInteger(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          let result = Int64(number.stringValue), result >= 0 else { return nil }
    return result
}
