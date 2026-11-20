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

    /// "Firn 1.0.0 (3), iOS 26.1, iPhone17,1".
    static func details(
        info: [String: Any]? = Bundle.main.infoDictionary,
        system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        model: String = model
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

    /// Apple's own code for the model ("iPhone17,1", "Mac16,10"). A table of
    /// friendly names would go stale with every new device; David can look a
    /// code up.
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
