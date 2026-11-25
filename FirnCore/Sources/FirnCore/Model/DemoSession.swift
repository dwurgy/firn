import Foundation

/// The demo's ready-made session (`--demo`, for the website's screenshots
/// and videos), as planned with David (docs/HISTORY.md, "Demo mode"): three
/// spaces with the same sites as the iPhone's screenshots, a few
/// tidied-away tabs, and two weeks of history. Every space gets a new data store each time, so a demo always
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
        let personal = Space(name: "Personal", color: "glacier", order: 0, dataStoreID: UUID(), lastChangedAt: now)
        let work = Space(name: "Work", color: "sage", order: 1, dataStoreID: UUID(), lastChangedAt: now)
        let home = Space(name: "Home", color: "heather", order: 2, dataStoreID: UUID(), lastChangedAt: now)

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

        // Personal: David's own sites in Basecamp, a story on screen, and
        // a group of Nordic shops.
        for (index, page) in [utuWeather, davidWurgler].enumerated() {
            add(page, to: personal, place: .basecamp, lastActiveAt: minutesAgo(Double(90 + index * 30)))
        }
        let personalTab = add(blunkHouse, to: personal, lastActiveAt: now)
        let nordic = group("Nordic Style", in: personal)
        add(audo, to: personal, group: nordic, lastActiveAt: minutesAgo(40))
        add(norseProjects, to: personal, group: nordic, lastActiveAt: minutesAgo(35))
        add(ourLegacy, to: personal, group: nordic, lastActiveAt: minutesAgo(30))
        add(snowPeak, to: personal, lastActiveAt: minutesAgo(20))
        add(firnArticle, to: personal, lastActiveAt: minutesAgo(15))
        add(bookOfRuth, to: personal, lastActiveAt: minutesAgo(10))
        for (index, page) in [glacierArticle, mountHood, kinfolk].enumerated() {
            add(page, to: personal, place: .drifted, lastActiveAt: daysAgo(12 + index), driftedAt: daysAgo(2 + index))
        }

        // Work: three loose tabs.
        let workTab = add(davidWurgler, to: work, lastActiveAt: minutesAgo(55))
        add(utuWeather, to: work, lastActiveAt: minutesAgo(60))
        add(kinfolk, to: work, lastActiveAt: minutesAgo(70))

        // Home: empty, for the empty page's Sunrise.

        // Firn was used each of the last two weeks' days.
        let usedDays = (0..<14).map { day(of: daysAgo($0)) }.sorted()

        let session = Session(
            spaces: [personal, work, home], groups: groups, tabs: tabs,
            window: WindowRecord(
                id: UUID(), activeSpaceID: personal.id, activeTabID: personalTab,
                spaceTabIDs: [work.id: workTab],
                sidebarWidth: 260, sidebarCollapsed: false
            ),
            usedDays: usedDays, unseenTidiedSpaceIDs: [personal.id]
        )

        // History: the space's pages, visited on a believable rhythm over
        // the last 14 days (everyday sites most days, the rest now and then).
        let pages: [(Space, [Page], [Page])] = [
            (personal, [utuWeather, davidWurgler],
             [blunkHouse, audo, norseProjects, ourLegacy, snowPeak, firnArticle, bookOfRuth, glacierArticle, mountHood, kinfolk]),
            (work, [davidWurgler, utuWeather, kinfolk], []),
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

    // MARK: The pages (the iPhone screenshots' sites, without Firn's own, which is
    // about to be rebranded; checked 2026-11-24)

    static let utuWeather = Page("Utu Weather", "https://utuweather.com/", icons: ["https://utuweather.com/apple-touch-icon.png"])
    static let davidWurgler = Page(
        "David Wurgler", "https://davidwurgler.com/",
        icons: ["https://davidwurgler.com/apple-touch-icon.png", "https://davidwurgler.com/favicon.ico"])
    // The hero shot.
    static let blunkHouse = Page(
        "Blunk House - Kinfolk", "https://www.kinfolk.com/stories/blunk-house/",
        icons: ["https://ik.imagekit.io/kinfolk/wp-content/themes/kinfolk/src/img/favicon/apple-touch-icon.png"])
    static let kinfolk = Page("Home - Kinfolk", "https://www.kinfolk.com/", icons: blunkHouse.icons.map(\.absoluteString))
    static let audo = Page(
        "Kitchen & Dining Room - Audo Copenhagen", "https://audocph.com/pages/kitchen-dining-room",
        icons: ["https://audocph.com/cdn/shop/files/Audo-Cph_Favicon_House_new_1b2ff315-3dff-4170-b4d9-066a2e757620.png?crop=center&height=180&v=1685541411&width=180"])
    static let norseProjects = Page(
        "Norse Projects", "https://norseprojects.com/",
        icons: ["https://norseprojects.com/cdn/shop/files/NPA_FAVICON-01_2bc60fed-c64f-4cdf-85b5-5dbbd4d726f5.png?v=1786091740&width=180"])
    static let ourLegacy = Page(
        "Our Legacy - Official Online Shop", "https://www.ourlegacy.com/",
        icons: ["https://www.ourlegacy.com/favicons/apple-touch-icon.png", "https://www.ourlegacy.com/favicons/favicon-32x32.png"])
    // Its only icon is a versioned theme file and the site refuses
    // non-browser requests, so none here: a demo shot loads the tab once
    // for its icon (`DemoShot`).
    static let snowPeak = Page(
        "Snow Peak USA - Japanese-Designed Camping Gear & Apparel | Snow Peak", "https://www.snowpeak.com/", icons: [])
    static let firnArticle = Page(
        "Firn - Wikipedia", "https://en.wikipedia.org/wiki/Firn",
        icons: ["https://en.wikipedia.org/apple-touch-icon.png", "https://en.wikipedia.org/favicon.ico"])
    static let bookOfRuth = Page(
        "The Book of Ruth | Bible Translation | Alabaster Co", "https://alabasterco.com/products/book-of-ruth",
        icons: ["https://alabasterco.com/cdn/shop/files/Alabaster_black_logo_jar_with_perfume_1-color.png?v=1751068595&width=180"])
    static let glacierArticle = Page("Glacier - Wikipedia", "https://en.wikipedia.org/wiki/Glacier", icons: firnArticle.icons.map(\.absoluteString))
    static let mountHood = Page("Mount Hood - Wikipedia", "https://en.wikipedia.org/wiki/Mount_Hood", icons: firnArticle.icons.map(\.absoluteString))

    static let allPages = [
        utuWeather, davidWurgler, blunkHouse, kinfolk, audo, norseProjects, ourLegacy, snowPeak, firnArticle,
        bookOfRuth, glacierArticle, mountHood,
    ]
}
