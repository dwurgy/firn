import Foundation

/// The demo's ready-made session (`--demo`, for the website's screenshots
/// and videos), as planned with David (docs/HISTORY.md, "Demo mode"): three
/// spaces of well-known sites, a few tidied-away tabs, and two weeks of
/// history. Every space gets a new data store each time, so a demo always
/// starts signed out of everything. Nothing here runs outside a demo.
public enum DemoSession {
    /// A visit to put in the demo's history.
    public struct Visit: Sendable {
        public let url: URL
        public let title: String
        public let time: Date
        public let dataStoreID: UUID
    }

    /// A page in the demo, with where its site's icon is (fetched at launch,
    /// so tiles and resting tabs don't show letters; nothing is bundled from
    /// other brands).
    struct Page {
        let title: String
        let url: URL
        let icons: [URL]

        init(_ title: String, _ url: String, icons: [String]) {
            self.title = title
            self.url = URL(string: url)!
            self.icons = icons.map { URL(string: $0)! }
        }
    }

    /// The session and its history, for a demo starting at `now`.
    public static func make(now: Date = .now) -> (session: Session, visits: [Visit]) {
        let personal = Space(name: "Personal", color: "sage", order: 0, dataStoreID: UUID(), lastChangedAt: now)
        let work = Space(name: "Work", color: "glacier", order: 1, dataStoreID: UUID(), lastChangedAt: now)
        let trip = Space(name: "Trip to Oregon", color: "ochre", order: 2, dataStoreID: UUID(), lastChangedAt: now)

        var tabs: [TabRecord] = []
        var groups: [GroupRecord] = []
        func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func daysAgo(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: now)! }

        @discardableResult
        func add(_ page: Page, to space: Space, place: Tab.Place = .open, group: GroupRecord? = nil,
                 lastActiveAt: Date, driftedAt: Date? = nil) -> UUID {
            let id = UUID()
            tabs.append(TabRecord(
                id: id, spaceID: space.id, place: place, url: page.url, title: page.title,
                homeURL: place == .basecamp ? page.url : nil, groupID: group?.id, order: tabs.count,
                lastActiveAt: lastActiveAt, openerTabID: nil, driftedAt: driftedAt, lastChangedAt: now
            ))
            return id
        }
        func group(_ name: String, in space: Space) -> GroupRecord {
            let record = GroupRecord(id: UUID(), spaceID: space.id, name: name, order: groups.count, folded: false, lastChangedAt: now)
            groups.append(record)
            return record
        }

        // Personal: everyday sites, weekend cooking, and a little reading.
        for (index, page) in [gmail, github, youtube, appleMusic].enumerated() {
            add(page, to: personal, place: .basecamp, lastActiveAt: minutesAgo(Double(90 + index * 30)))
        }
        let cooking = group("Weekend cooking", in: personal)
        add(pumpkinBread, to: personal, group: cooking, lastActiveAt: minutesAgo(40))
        add(galette, to: personal, group: cooking, lastActiveAt: minutesAgo(35))
        add(firnArticle, to: personal, lastActiveAt: minutesAgo(20))
        let personalTab = add(craterLake, to: personal, lastActiveAt: now)
        for (index, page) in [glacierArticle, mountHood, ciderCaramels].enumerated() {
            add(page, to: personal, place: .drifted, lastActiveAt: daysAgo(12 + index), driftedAt: daysAgo(2 + index))
        }

        // Work: a launch, and Firn's own site.
        for (index, page) in [calendar, slack, notion].enumerated() {
            add(page, to: work, place: .basecamp, lastActiveAt: minutesAgo(Double(120 + index * 30)))
        }
        let launch = group("Launch", in: work)
        add(guidelines, to: work, group: launch, lastActiveAt: minutesAgo(70))
        add(reviewGuidelines, to: work, group: launch, lastActiveAt: minutesAgo(65))
        add(materials, to: work, lastActiveAt: minutesAgo(60))
        let workTab = add(firnSite, to: work, lastActiveAt: minutesAgo(55))

        // Trip to Oregon: a nod to First light.
        let sistersGroup = group("Sisters", in: trip)
        let tripTab = add(sisters, to: trip, group: sistersGroup, lastActiveAt: minutesAgo(50))
        add(smithRock, to: trip, group: sistersGroup, lastActiveAt: minutesAgo(48))
        add(sistersCoffee, to: trip, group: sistersGroup, lastActiveAt: minutesAgo(46))
        add(map, to: trip, lastActiveAt: minutesAgo(45))
        add(weather, to: trip, lastActiveAt: minutesAgo(44))

        // Firn was used each of the last two weeks' days.
        let usedDays = (0..<14).map { day(of: daysAgo($0)) }.sorted()

        let session = Session(
            spaces: [personal, work, trip], groups: groups, tabs: tabs,
            window: WindowRecord(
                id: UUID(), activeSpaceID: personal.id, activeTabID: personalTab,
                spaceTabIDs: [work.id: workTab, trip.id: tripTab],
                sidebarWidth: 260, sidebarCollapsed: false
            ),
            usedDays: usedDays, unseenTidiedSpaceIDs: [personal.id]
        )

        // History: the space's pages, visited on a believable rhythm over
        // the last 14 days (everyday sites most days, the rest now and then).
        let pages: [(Space, [Page], [Page])] = [
            (personal, [gmail, youtube, github, appleMusic], [pumpkinBread, galette, firnArticle, craterLake, glacierArticle, mountHood, ciderCaramels]),
            (work, [calendar, slack, notion], [guidelines, reviewGuidelines, materials, firnSite]),
            (trip, [], [sisters, smithRock, sistersCoffee, map, weather]),
        ]
        var visits: [Visit] = []
        for (space, everyday, others) in pages {
            for day in 0..<14 {
                let base = Calendar.current.startOfDay(for: daysAgo(day))
                func visit(_ page: Page, hour: Double) {
                    let time = base.addingTimeInterval(hour * 3600)
                    guard time < now else { return }
                    visits.append(Visit(url: page.url, title: page.title, time: time, dataStoreID: space.dataStoreID))
                }
                for (index, page) in everyday.enumerated() where (day + index) % 3 != 2 {
                    visit(page, hour: 8.5 + Double(index) * 1.25)
                }
                for (index, page) in others.enumerated() where (day * 2 + index) % 5 == 0 {
                    visit(page, hour: 13 + Double(index) * 0.75)
                }
            }
        }
        return (session, visits.sorted { $0.time < $1.time })
    }

    /// Fetches each demo site's icon once, for the tabs still without one
    /// (tiles and tabs that haven't loaded). Only the demo's fixed https
    /// icon addresses are asked, through `SiteIcon`'s private fetch (no
    /// cookies, cache, or sign-ins).
    @MainActor public static func fetchIcons(for store: BrowserStore) async {
        let hosts = Set(store.tabs.filter { $0.icon == nil }.compactMap { $0.url?.host() })
        let icons = await withTaskGroup(of: (String, Data?).self) { group in
            for host in hosts {
                let candidates = iconAddresses(for: host)
                guard !candidates.isEmpty else { continue }
                group.addTask { (host, await SiteIcon.fetch(candidates, userAgent: nil)) }
            }
            var found: [String: Data] = [:]
            for await (host, png) in group { found[host] = png }
            return found
        }
        for tab in store.tabs {
            if let host = tab.url?.host(), let png = icons[host] { tab.setIconIfMissing(png) }
        }
    }

    /// The icon addresses for a demo site: the welcome's, where it has the
    /// site, else the demo's own.
    static func iconAddresses(for host: String) -> [URL] {
        if let site = WelcomeSite.suggestions.first(where: { $0.url.host() == host }) {
            return (site.prefer + site.icons).filter { $0.scheme == "https" }
        }
        return allPages.first { $0.url.host() == host }?.icons ?? []
    }

    private static func day(of date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: The pages (checked signed out, 2026-10-26)

    static let gmail = Page("Gmail", "https://mail.google.com/", icons: [])
    static let github = Page("GitHub", "https://github.com/", icons: ["https://github.com/apple-touch-icon.png", "https://github.com/favicon.ico"])
    static let youtube = Page("YouTube", "https://www.youtube.com/", icons: [])
    static let appleMusic = Page("Apple Music", "https://music.apple.com/", icons: ["https://music.apple.com/apple-touch-icon.png", "https://music.apple.com/favicon.ico"])
    static let pumpkinBread = Page(
        "pumpkin bread – smitten kitchen", "https://smittenkitchen.com/2016/10/pumpkin-bread/",
        icons: ["https://smittenkitchen.com/apple-touch-icon.png", "https://smittenkitchen.com/favicon.ico"])
    static let galette = Page(
        "butternut squash and caramelized onion galette – smitten kitchen",
        "https://smittenkitchen.com/2007/10/butternut-squash-and-caramelized-onion-galette/", icons: pumpkinBread.icons.map(\.absoluteString))
    static let firnArticle = Page(
        "Firn - Wikipedia", "https://en.wikipedia.org/wiki/Firn",
        icons: ["https://en.wikipedia.org/apple-touch-icon.png", "https://en.wikipedia.org/favicon.ico"])
    static let craterLake = Page(
        "Crater Lake National Park (U.S. National Park Service)", "https://www.nps.gov/crla/index.htm",
        icons: ["https://www.nps.gov/favicon.ico"])
    static let glacierArticle = Page("Glacier - Wikipedia", "https://en.wikipedia.org/wiki/Glacier", icons: firnArticle.icons.map(\.absoluteString))
    static let mountHood = Page("Mount Hood - Wikipedia", "https://en.wikipedia.org/wiki/Mount_Hood", icons: firnArticle.icons.map(\.absoluteString))
    static let ciderCaramels = Page(
        "apple cider caramels – smitten kitchen", "https://smittenkitchen.com/2012/10/apple-cider-caramels/",
        icons: pumpkinBread.icons.map(\.absoluteString))

    static let calendar = Page("Google Calendar", "https://calendar.google.com/", icons: [])
    static let slack = Page(
        "Slack", "https://app.slack.com/",
        icons: ["https://a.slack-edge.com/9cc0056/img/icons/favicon-32.png", "https://slack.com/favicon.ico"])
    static let notion = Page(
        "Notion", "https://www.notion.so/",
        icons: ["https://www.notion.so/front-static/logo-ios.png", "https://www.notion.so/front-static/favicon.ico"])
    static let guidelines = Page(
        "Human Interface Guidelines | Apple Developer Documentation", "https://developer.apple.com/design/human-interface-guidelines/",
        icons: ["https://developer.apple.com/apple-touch-icon.png", "https://developer.apple.com/favicon.ico"])
    static let reviewGuidelines = Page(
        "App Review Guidelines - Apple Developer", "https://developer.apple.com/app-store/review/guidelines/",
        icons: guidelines.icons.map(\.absoluteString))
    static let materials = Page(
        "Materials | Apple Developer Documentation", "https://developer.apple.com/design/human-interface-guidelines/materials",
        icons: guidelines.icons.map(\.absoluteString))
    static let firnSite = Page(
        "Firn | A calm browser, made for Mac", "https://firnbrowser.com/",
        icons: ["https://firnbrowser.com/assets/favicon/firn-favicon-180.png", "https://firnbrowser.com/assets/favicon/favicon.ico"])

    static let sisters = Page(
        "Visit Sisters Oregon", "https://www.sisterscountry.com/", icons: ["https://www.sisterscountry.com/favicon.ico"])
    static let smithRock = Page(
        "Smith Rock State Park - Oregon State Parks", "https://stateparks.oregon.gov/index.cfm?do=park.profile&parkId=36",
        icons: ["https://stateparks.oregon.gov/favicon.ico"])
    static let sistersCoffee = Page(
        "Sisters Coffee Company", "https://sisterscoffee.com/",
        icons: ["https://sisterscoffee.com/cdn/shop/files/PRIMARY-context-needed_BLACK_5_32x32.png?v=1744130133"])
    static let map = Page(
        "Sisters, Oregon - Apple Maps", "https://maps.apple.com/place?coordinate=44.291%2C-121.549&name=Sisters%2C%20Oregon",
        icons: ["https://maps.apple.com/favicon.ico"])
    static let weather = Page(
        "7-Day Forecast for Sisters, OR", "https://forecast.weather.gov/MapClick.php?lat=44.291&lon=-121.549",
        icons: ["https://forecast.weather.gov/favicon.ico"])

    static let allPages = [
        gmail, github, youtube, appleMusic, pumpkinBread, galette, firnArticle, craterLake, glacierArticle, mountHood,
        ciderCaramels, calendar, slack, notion, guidelines, reviewGuidelines, materials, firnSite,
        sisters, smithRock, sistersCoffee, map, weather,
    ]
}
