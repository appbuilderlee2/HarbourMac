import Foundation

public struct BridgeEvent {
    public let kind: String
    public let fields: [String]
    public static func parse(_ line: String, token: String) -> BridgeEvent? {
        let pieces = line.components(separatedBy: "\t")
        guard pieces.count >= 2, pieces[0] == "@@HARBOUR:" + token,
              ["begin", "row", "select", "confirm", "config", "option"].contains(pieces[1]) else { return nil }
        var fields: [String] = []
        for field in pieces.dropFirst(2) {
            guard let bytes = Data(base64Encoded: field), let value = String(data: bytes, encoding: .utf8) else { return nil }
            fields.append(value)
        }
        let counts = ["begin": 2, "row": 5, "select": 0, "confirm": 1, "config": 1, "option": 2]
        guard fields.count == counts[pieces[1]] else { return nil }
        return BridgeEvent(kind: pieces[1], fields: fields)
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
