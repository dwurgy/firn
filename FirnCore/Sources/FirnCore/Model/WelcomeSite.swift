import Foundation

/// An everyday site the welcome offers for Basecamp: the calm essentials
/// (mail, calendar, files, an assistant, shopping, video, and music), no
/// social feeds. The Electron app's eight, unchanged (docs/electron-welcome/welcome.ts).
public struct WelcomeSite: Identifiable, Sendable {
    public let name: String
    public let url: URL
    /// Known newest icons, tried first (Google's 2026 icons are newer than
    /// what its signed-out pages list).
    let prefer: [URL]
    /// The site's usual icons, tried next.
    let icons: [URL]

    public var id: URL { url }

    init(_ name: String, _ url: String, prefer: [String] = [], icons: [String]) {
        self.name = name
        self.url = URL(string: url)!
        self.prefer = prefer.map { URL(string: $0)! }
        self.icons = icons.map { URL(string: $0)! }
    }

    /// Its icon, fetched now (the welcome's sites are fetched, not bundled,
    /// so they're up to date): the first of `prefer`, then of `icons`, that
    /// gives a usable image, as a small PNG; nil if none does (the welcome
    /// then shows Firn's letter tile). Only these fixed https addresses are
    /// asked, through `SiteIcon`'s private fetch (no cookies, cache, or
    /// sign-ins) and its size and pixel caps.
    public func fetchIcon() async -> Data? {
        let candidates = (prefer + icons).filter { $0.scheme == "https" }
        for url in candidates {
            if Task.isCancelled { return nil }
            if let png = await SiteIcon.fetch([url], userAgent: nil) { return png }
        }
        return nil
    }

    public static let suggestions: [WelcomeSite] = [
        WelcomeSite(
            "Gmail", "https://mail.google.com/",
            prefer: [
                "https://www.gstatic.com/images/branding/productlogos/gmail_2026/v2/web-64dp/logo_gmail_2026_color_2x_web_64dp.png",
                "https://ssl.gstatic.com/images/branding/productlogos/gmail_2026/v2/ico/gmail_2026_256dp.ico",
            ],
            icons: [
                "https://ssl.gstatic.com/ui/v1/icons/mail/rfr/gmail.ico",
                "https://mail.google.com/favicon.ico",
            ]),
        WelcomeSite(
            "Outlook", "https://outlook.live.com/mail/",
            icons: [
                "https://res.cdn.office.net/assets/mail/pwa/v1/pngs/apple-touch-icon.png",
                "https://outlook.live.com/favicon.ico",
            ]),
        WelcomeSite(
            "Calendar", "https://calendar.google.com/",
            prefer: [
                "https://www.gstatic.com/images/branding/productlogos/calendar_2026/v2/web-64dp/logo_calendar_2026_color_2x_web_64dp.png",
                "https://ssl.gstatic.com/images/branding/productlogos/calendar_2026/v2/ico/calendar_2026_256dp.ico",
            ],
            icons: [
                "https://ssl.gstatic.com/calendar/images/dynamiclogo_2020q4/calendar_31_2x.png",
                "https://calendar.google.com/googlecalendar/images/favicons_2020q4/calendar_31.ico",
            ]),
        WelcomeSite(
            "Drive", "https://drive.google.com/",
            prefer: [
                "https://www.gstatic.com/images/branding/productlogos/drive_2026/v2/web-64dp/logo_drive_2026_color_2x_web_64dp.png",
                "https://ssl.gstatic.com/images/branding/productlogos/drive_2026/v2/ico/drive_2026_256dp.ico",
            ],
            icons: [
                "https://ssl.gstatic.com/images/branding/product/2x/drive_2020q4_48dp.png",
                "https://drive.google.com/favicon.ico",
            ]),
        WelcomeSite(
            "Claude", "https://claude.ai/",
            icons: [
                "https://claude.ai/apple-touch-icon.png",
                "https://claude.ai/favicon.ico",
            ]),
        WelcomeSite(
            "Amazon", "https://www.amazon.com/",
            icons: ["https://www.amazon.com/favicon.ico"]),
        WelcomeSite(
            "YouTube", "https://www.youtube.com/",
            icons: [
                "https://www.gstatic.com/youtube/img/branding/favicon/favicon_144x144.png",
                "https://www.youtube.com/favicon.ico",
            ]),
        WelcomeSite(
            "Spotify", "https://open.spotify.com/",
            icons: [
                "https://open.spotify.com/favicon.ico",
                "https://www.spotify.com/favicon.ico",
            ]),
    ]
}
