import Foundation

/// Send Feedback: a blank email to David in the person's own mail app, with
/// only Firn's version, the system's version, and the device's model at the
/// bottom (nothing from their tabs, spaces, or history). Firn sends nothing
/// itself: the draft opens in their mail app, and they send it or don't.
public enum FeedbackEmail {
    public static let address = "hello@firnbrowser.com"

    /// The draft for this device, as a `mailto:` link.
    public static var url: URL { url(details: details()) }

    /// A `mailto:` link whose body is two blank lines to write in, a rule,
    /// and `details`.
    static func url(details: String) -> URL {
        var link = URLComponents()
        link.scheme = "mailto"
        link.path = address
        // Mail wants line breaks as CR LF (RFC 6068).
        link.queryItems = [
            URLQueryItem(name: "subject", value: "Firn feedback"),
            URLQueryItem(name: "body", value: "\r\n\r\n---\r\n\(details)"),
        ]
        // The pieces are all Firn's own, so this can't fail.
        return link.url ?? URL(string: "mailto:\(address)")!
    }

    /// "Firn 1.0.0 (3), iOS 26.1, iPhone 16 Pro".
    static func details(
        info: [String: Any]? = Bundle.main.infoDictionary,
        system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        model: String = deviceName(for: model)
    ) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var number = "\(system.majorVersion).\(system.minorVersion)"
        if system.patchVersion > 0 { number += ".\(system.patchVersion)" }
        var line = "Firn \(version) (\(build)), \(systemName) \(number)"
        if !model.isEmpty { line += ", \(model)" }
        return line
    }

    private static var systemName: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }

    /// What the draft calls the device. Apple's codes run a number ahead of
    /// the names (an iPhone 16 Pro is "iPhone17,1"), so a code in the draft
    /// reads as the wrong phone (David, 2026-11-20). Known iPhones get their
    /// real name; any other iPhone or iPad is just "iPhone" or "iPad", never
    /// wrong, only less exact. A Mac keeps its code, which reads as no
    /// product's name.
    static func deviceName(for code: String) -> String {
        if let name = iPhoneNames[code] { return name }
        if code.hasPrefix("iPhone") { return "iPhone" }
        if code.hasPrefix("iPad") { return "iPad" }
        return code
    }

    /// Every iPhone that runs iOS 26. Add each autumn's new ones; until
    /// then they're "iPhone".
    private static let iPhoneNames: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
    ]

    /// Apple's own code for the model ("iPhone17,1", "Mac16,10").
    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        #if os(macOS)
        let name = "hw.model"
        #else
        let name = "hw.machine"
        #endif
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
