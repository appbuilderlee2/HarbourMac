import Foundation
import FoundationXML

public enum SystemData {
    public static func percentage(_ value: Any?) -> Double? {
        let result: Double?
        if let number = value as? NSNumber { result = number.doubleValue }
        else if let string = value as? String {
            result = Double(string.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: ""))
        } else { result = nil }
        guard let value = result, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
    // Mole uses zero for unavailable thermal values. Do not claim that zero means stopped.
    public static func positiveReading(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, n.doubleValue.isFinite, n.doubleValue > 0 else { return nil }
        return n.doubleValue
    }
    public static func brewUpdates(_ data: Data) throws -> [PackageUpdate] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]],
              let casks = root["casks"] as? [[String: Any]] else {
            throw SystemDataError.invalidResponse
        }
        return [(formulae, false), (casks, true)].flatMap { rows, cask in
            rows.compactMap { row in
                guard let name = row["name"] as? String, !name.isEmpty,
                      name.range(of: #"^[A-Za-z0-9][A-Za-z0-9@+._/-]*$"#, options: .regularExpression) != nil,
                      let latest = row["current_version"] as? String else { return nil }
                let installed = (row["installed_versions"] as? [String])?.joined(separator: ", ")
                    ?? row["installed_versions"] as? String ?? "未提供"
                return PackageUpdate(name: name, installed: installed, latest: latest, cask: cask)
            }
        }
    }
    public static func accessories(_ data: Data) throws -> [AccessoryReading] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else {
            throw SystemDataError.invalidResponse
        }
        var result: [AccessoryReading] = []
        for controller in controllers {
            for group in ["device_connected", "device_not_connected"] {
                for devices in controller[group] as? [[String: Any]] ?? [] {
                    for name in devices.keys.sorted() {
                        guard let details = devices[name] as? [String: Any] else { continue }
                        let levels = details.keys.sorted().filter { $0.hasPrefix("device_batteryLevel") }.compactMap { key -> BatteryLevel? in
                            guard let level = percentage(details[key]) else { return nil }
                            let labels = ["device_batteryLevelMain": "電量", "device_batteryLevelLeft": "左耳",
                                          "device_batteryLevelRight": "右耳", "device_batteryLevelCase": "充電盒"]
                            return BatteryLevel(label: labels[key] ?? "電量", value: level)
                        }
                        result.append(AccessoryReading(name: name, connected: group == "device_connected", levels: levels))
                    }
                }
            }
        }
        return result
    }
}
public enum SystemDataError: Error { case invalidResponse }
public struct PackageUpdate: Identifiable {
    public var id: String { (cask ? "cask:" : "formula:") + name }
    public let name: String
    public let installed: String
    public let latest: String
    public let cask: Bool
}
public struct BatteryLevel { public let label: String; public let value: Double }
public struct AccessoryReading: Identifiable {
    public let id = UUID()
    public let name: String
    public let connected: Bool
    public let levels: [BatteryLevel]
}

// Read version metadata only. Never download enclosures or bypass an application's updater.
public final class AppcastReader: NSObject, XMLParserDelegate {
    public struct Release {
        public var version = ""
        public var minimumOS = ""
        public var channel = ""
    }
    public private(set) var releases: [Release] = []
    private var current: Release?
    private var element = ""
    private var buffer = ""
    public func read(_ data: Data) throws -> [Release] {
        releases = []; current = nil
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse() else { throw SystemDataError.invalidResponse }
        return releases
    }
    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        element = name; buffer = ""
        if name == "item" { current = Release() }
        if name == "enclosure", let version = attributes["sparkle:shortVersionString"] { current?.version = version }
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }
    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "sparkle:shortVersionString" { current?.version = text }
        if name == "sparkle:minimumSystemVersion" { current?.minimumOS = text }
        if name == "sparkle:channel" { current?.channel = text }
        if name == "item", let release = current {
            if !release.version.isEmpty { releases.append(release) }
            current = nil
        }
        buffer = ""
    }
    public static func numericVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil
    }
    public static func newer(_ candidate: String, than installed: String) -> Bool {
        numericVersion(candidate) && numericVersion(installed) && candidate.compare(installed, options: .numeric) == .orderedDescending
    }
}
