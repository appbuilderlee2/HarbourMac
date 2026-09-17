import Foundation

public struct BridgeEvent {
    public let kind: String
    public let fields: [String]
    public static func parse(_ line: String, token: String) -> BridgeEvent? {
        let pieces = line.components(separatedBy: "\t")
        let counts = ["begin": 2, "row": 5, "select": 0, "confirm": 1, "config": 1, "option": 2,
                      "clean_preview_begin": 3, "clean_preview_item": 7, "clean_preview_end": 3]
        guard pieces.count >= 2, pieces[0] == "@@HARBOUR:" + token,
              let count = counts[pieces[1]], pieces.count == count + 2 else { return nil }
        var fields: [String] = []
        for field in pieces.dropFirst(2) {
            guard let bytes = Data(base64Encoded: field), let value = String(data: bytes, encoding: .utf8) else { return nil }
            fields.append(value)
        }
        let event = BridgeEvent(kind: pieces[1], fields: fields)
        if event.kind.hasPrefix("clean_preview_"), CleanPreviewEvent(event) == nil { return nil }
        return event
    }

    // Authenticated but malformed preview frames must not be silently logged
    // and then mistaken for a valid empty preview by the state machine.
    public static func isCleanPreviewFrame(_ line: String, token: String) -> Bool {
        line.hasPrefix("@@HARBOUR:" + token + "\tclean_preview_")
    }
}
public enum TextFormat {
    public static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
    }
    public static func selection(_ ids: Set<Int>, available: Set<Int>) -> String? {
        guard !ids.isEmpty, ids.isSubset(of: available), ids.allSatisfy({ $0 >= 0 }) else { return nil }
        return ids.sorted().map(String.init).joined(separator: ",") + "\n"
    }
}

public struct CleanPreviewItem: Identifiable {
    public let id: Int
    public let identity: String
    public let category: String
    public let path: String
    public let bytes: Int64?
    public let itemCount: Int64
}

public enum CleanPreviewEvent {
    case begin(systemIncluded: Bool)
    case item(CleanPreviewItem)
    case end(rowCount: Int, scanExitCode: Int32, sizingTimeoutCount: Int64)

    private static func integer(_ text: String) -> Int64? {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              text == "0" || !text.hasPrefix("0") else { return nil }
        return Int64(text)
    }
    private static func boolean(_ text: String) -> Bool? {
        switch text { case "true": return true; case "false": return false; default: return nil }
    }
    public init?(_ event: BridgeEvent) {
        let fields = event.fields
        switch event.kind {
        case "clean_preview_begin":
            guard fields.count == 3, fields[0] == "1", fields[1] == "mole.clean.deduplicated-ledger",
                  let system = Self.boolean(fields[2]) else { return nil }
            self = .begin(systemIncluded: system)
        case "clean_preview_item":
            guard fields.count == 7, let rawID = Self.integer(fields[0]), let id = Int(exactly: rawID),
                  !fields[1].isEmpty, !fields[2].isEmpty, !fields[3].isEmpty,
                  let kib = Self.integer(fields[4]), let count = Self.integer(fields[5]), count > 0,
                  let known = Self.boolean(fields[6]) else { return nil }
            let bytes = kib.multipliedReportingOverflow(by: 1024)
            guard !bytes.overflow else { return nil }
            self = .item(CleanPreviewItem(id: id, identity: fields[1], category: fields[2], path: fields[3],
                                         bytes: known ? bytes.partialValue : nil, itemCount: count))
        case "clean_preview_end":
            guard fields.count == 3, let rawCount = Self.integer(fields[0]), let count = Int(exactly: rawCount),
                  let rc = Self.integer(fields[1]), rc <= 255, let timeouts = Self.integer(fields[2]) else { return nil }
            self = .end(rowCount: count, scanExitCode: Int32(rc), sizingTimeoutCount: timeouts)
        default: return nil
        }
    }
}

/// A read-only report, never a deletion selection or target authority.
public struct CleanPreviewSession {
    public private(set) var items: [CleanPreviewItem] = []
    public private(set) var categories: [String] = []
    public private(set) var knownBytes: Int64 = 0
    public private(set) var unknownSizeCount = 0
    public private(set) var systemIncluded = false
    public private(set) var sizingTimeoutCount: Int64 = 0
    public private(set) var isInvalid = false
    public private(set) var isSuccessful = false
    private var began = false
    private var ended = false
    private var finished = false
    private var scanExitCode: Int32?
    private var identities: Set<String> = []
    public init() {}

    public mutating func invalidate() { isInvalid = true; isSuccessful = false }
    public mutating func consume(_ event: BridgeEvent) {
        guard !isInvalid, !finished, let parsed = CleanPreviewEvent(event) else { invalidate(); return }
        switch parsed {
        case .begin(let system):
            guard !began, !ended else { invalidate(); return }
            began = true; systemIncluded = system
        case .item(let item):
            guard began, !ended, item.id == items.count, !identities.contains(item.identity) else { invalidate(); return }
            if let bytes = item.bytes {
                let total = knownBytes.addingReportingOverflow(bytes)
                guard !total.overflow else { invalidate(); return }
                knownBytes = total.partialValue
            } else { unknownSizeCount += 1 }
            identities.insert(item.identity)
            if !categories.contains(item.category) { categories.append(item.category) }
            items.append(item)
        case .end(let count, let rc, let timeouts):
            guard began, !ended, count == items.count else { invalidate(); return }
            ended = true; scanExitCode = rc; sizingTimeoutCount = timeouts
        }
    }
    public mutating func finish(exitCode: Int32) {
        guard !finished else { invalidate(); return }
        finished = true
        guard !isInvalid, began, ended, scanExitCode == 0, exitCode == 0 else { invalidate(); return }
        isSuccessful = true
    }
}
