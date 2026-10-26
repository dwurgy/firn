import FirnCore
import SwiftUI

/// History › Show History (⌘Y): the space on screen's visits, newest first,
/// grouped by day, with a search field. Double-click or Return opens a visit
/// as a new tab in the browser window; Delete (or the right-click menu)
/// removes visits, and Clear History… a stretch of time. Spaces sharing
/// sign-ins share this history; a separate space only ever shows its own.
///
/// Visits are read a page at a time as the list scrolls, and again whenever
/// the window comes to the front, so pages visited meanwhile appear.
struct HistoryWindow: View {
    let window: WindowModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var search = ""
    @State private var visits: [HistoryVisit] = []
    @State private var days: [Day] = []
    @State private var loaded = false
    @State private var reachedEnd = false
    @State private var loadingMore = false
    @State private var icons: [String: Data] = [:]
    @State private var selection: Set<Int64> = []
    /// The space whose history Clear History… is asking about.
    @State private var clearing: Space?

    /// One day's visits, under its heading.
    private struct Day: Identifiable {
        let start: Date
        let visits: [HistoryVisit]
        var id: Date { start }
    }

    private var store: BrowserStore { window.store }
    private var space: Space { store.activeSpace }

    /// What's read: a new space (with other history) or new words start over.
    private var readKey: String { "\(space.dataStoreID)\n\(search)" }

    var body: some View {
        // The list is always there, even empty (the message lies over it):
        // the toolbar's glass then looks the same with or without results,
        // instead of turning into a solid bar when there's nothing to scroll.
        list
            .overlay { emptyMessage }
            .frame(minWidth: 460, minHeight: 360)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .modifier(PageBackground())
            .navigationTitle("History")
            .navigationSubtitle(space.name)
            .searchable(text: $search, placement: .toolbar, prompt: "Search History")
            .sheet(item: $clearing) { space in
                ClearHistorySheet(space: space, sharing: store.spacesSharingHistory(with: space)) { range in
                    Task {
                        await store.clearHistory(range, in: space)
                        await readFirstPage(replacing: true)
                    }
                }
                .presentationBackground(Theme.page)
            }
            .task(id: readKey) { await readFirstPage(replacing: true) }
            .onChange(of: activeState) { _, state in
                guard state == .key, loaded else { return }
                Task { await readFirstPage(replacing: false) }
            }
            // History › Clear History… opens this window and asks here.
            .onAppear(perform: answerClearRequest)
            .onChange(of: window.asksToClearHistory) { answerClearRequest() }
    }

    private func answerClearRequest() {
        guard window.asksToClearHistory else { return }
        window.asksToClearHistory = false
        clearing = space
    }

    @ViewBuilder private var emptyMessage: some View {
        if loaded && visits.isEmpty {
            if isSearching {
                EmptyHistory(symbol: "magnifyingglass", title: "No results",
                             line: "Nothing in \(space.name)'s history matches \u{201C}\(search.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}.")
            } else {
                EmptyHistory(symbol: "clock", title: "No history yet",
                             line: "Pages you visit in \(space.name) appear here.")
            }
        }
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A quiet line along the bottom, like the footnotes in Settings, and
    /// Clear History… beside it in Firn's quiet wash, the same button as the
    /// sheet's Cancel. The page color under it, so rows slip out of sight
    /// at its edge with no line.
    private var footer: some View {
        HStack(spacing: 12) {
            Text("History stays on this Mac for a year.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Button("Clear History…") { clearing = space }
                .buttonStyle(SheetButtonStyle(prominent: false))
                .disabled(loaded && visits.isEmpty && !isSearching)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background(Theme.page)
    }

    private var list: some View {
        List(selection: $selection) {
            // Day headings are ordinary rows that scroll away, not section
            // headers: macOS pins those to the top with a line under them.
            ForEach(days) { day in
                Text(heading(for: day.start))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, day.id == days.first?.id ? 4 : Theme.sectionSpacing)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
                ForEach(day.visits) { visit in
                    row(visit)
                        .tag(visit.id)
                        .listRowSeparator(.hidden)
                        .onAppear { if visit.id == visits.last?.id { readMore() } }
                }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: Int64.self) { ids in
            if !ids.isEmpty {
                Button(ids.count == 1 ? "Open in New Tab" : "Open \(ids.count) Pages in New Tabs") { open(ids) }
                Divider()
                Button("Delete") { delete(ids) }
                if let site = onlySite(of: ids) {
                    Button("Delete All from \(site)") { deleteAll(from: site) }
                }
            }
        } primaryAction: { ids in
            open(ids)
        }
        .onDeleteCommand { delete(selection) }
    }

    /// The one site all these visits are from, if there's just one.
    private func onlySite(of ids: Set<Int64>) -> String? {
        let sites = Set(visits.filter { ids.contains($0.id) }.map(\.site))
        return sites.count == 1 ? sites.first : nil
    }

    private func row(_ visit: HistoryVisit) -> some View {
        HStack(spacing: 10) {
            SiteMark(site: visit.site, icon: icons[visit.url.host(percentEncoded: false)?.lowercased() ?? ""])
            VStack(alignment: .leading, spacing: 1) {
                Text(visit.title.isEmpty ? visit.site : visit.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                Text(visit.site)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(visit.visitedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-click or press Return to open it in a new tab; press Delete to remove it")
    }

    /// "Today", "Yesterday", or the date ("Thursday, October 22"; the year
    /// only when it isn't this one).
    private func heading(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        let style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        return day.formatted(sameYear ? style : style.year())
    }

    // MARK: Reading

    /// The newest visits. Replacing starts the list over (new words, or
    /// another space); otherwise they're laid over what's shown, keeping the
    /// older visits already read further down.
    private func readFirstPage(replacing: Bool) async {
        let fresh = await store.historyVisits(in: space, matching: search)
        guard !Task.isCancelled else { return }
        if replacing {
            reachedEnd = fresh.count < BrowserStore.historyPageSize
            show(fresh)
            selection = []
        } else {
            let oldest = fresh.last?.visitedAt ?? .distantPast
            show(fresh + visits.filter { $0.visitedAt < oldest })
        }
        loaded = true
    }

    /// The next, older page, once the last row shows.
    private func readMore() {
        guard !reachedEnd, !loadingMore, let oldest = visits.last?.visitedAt else { return }
        loadingMore = true
        let key = readKey
        Task {
            let older = await store.historyVisits(in: space, matching: search, before: oldest)
            loadingMore = false
            guard key == readKey else { return }
            reachedEnd = older.count < BrowserStore.historyPageSize
            show(visits + older)
        }
    }

    private func show(_ newVisits: [HistoryVisit]) {
        visits = newVisits
        let calendar = Calendar.current
        var grouped: [Day] = []
        var current: [HistoryVisit] = []
        var currentStart: Date?
        for visit in newVisits {
            let start = calendar.startOfDay(for: visit.visitedAt)
            if start != currentStart, let currentStart {
                grouped.append(Day(start: currentStart, visits: current))
                current = []
            }
            currentStart = start
            current.append(visit)
        }
        if let currentStart { grouped.append(Day(start: currentStart, visits: current)) }
        days = grouped
        readIcons()
    }

    /// Site icons from this history's own tabs, where there are any (history
    /// keeps no icons of its own).
    private func readIcons() {
        let dataStoreID = space.dataStoreID
        let spaceIDs = Set(store.spaces.filter { $0.dataStoreID == dataStoreID }.map(\.id))
        var found: [String: Data] = [:]
        for tab in store.tabs where spaceIDs.contains(tab.spaceID) {
            guard let host = tab.url?.host(percentEncoded: false)?.lowercased(), found[host] == nil,
                  let icon = tab.icon else { continue }
            found[host] = icon
        }
        icons = found
    }

    // MARK: Deleting

    /// Deletes the visits at once (no asking: it's only history, and
    /// Safari doesn't ask either); their rows leave the list.
    private func delete(_ ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        let space = space
        removeRows { ids.contains($0.id) }
        Task { await store.deleteHistory(visits: Array(ids), in: space) }
    }

    /// Deletes every visit to `site`, including those not read yet.
    private func deleteAll(from site: String) {
        let space = space
        removeRows { $0.site == site }
        Task { await store.deleteHistory(fromSite: site, in: space) }
    }

    private func removeRows(where gone: (HistoryVisit) -> Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            show(visits.filter { !gone($0) })
        }
        selection = selection.filter { id in visits.contains { $0.id == id } }
    }

    // MARK: Opening

    /// Opens the visits as new tabs, where new tabs go, and brings the
    /// browser window forward. Only web addresses, whatever the file holds.
    private func open(_ ids: Set<Int64>) {
        let urls = visits.filter { ids.contains($0.id) }.map(\.url).filter(WebAddress.isWebURL)
        guard !urls.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            for url in urls { store.openTab(url) }
        }
        openWindow(id: "browser")
    }
}

/// Firn's page color across the whole window, under the toolbar too, as
/// the page sits in the browser; the toolbar's glass lies over it.
struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.containerBackground(Theme.page, for: .window)
        } else {
            content.background(Theme.page.ignoresSafeArea())
        }
    }
}

/// Shown over the list when there's nothing in it: a faint symbol,
/// a short title, and one plain line, centered in the window.
private struct EmptyHistory: View {
    let symbol: String
    let title: String
    let line: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.faint)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(line)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(.bottom, 40) // sits a little above the middle, where the eye rests
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Clear History…: how far back to clear, and whose history it is. Laid
/// out like Firn's other sheets (Edit password): title, one plain line, the
/// choice, then Cancel and the ink button. All four choices show at once,
/// as radio buttons, like the choices in Settings.
private struct ClearHistorySheet: View {
    let space: Space
    let sharing: [Space]
    let clear: (HistoryClearRange) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var range = HistoryClearRange.lastHour

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Clear history")
                    .font(Theme.panelTitleFont)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Clear", selection: $range) {
                ForEach(HistoryClearRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .tint(Theme.accent)
            .accessibilityLabel("Clear")
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SheetButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button("Clear History") {
                    clear(range)
                    dismiss()
                }
                .buttonStyle(SheetButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private var explanation: String {
        let stays = "Sign-ins and open tabs stay."
        guard sharing.count > 1 else {
            return "Removes pages you visited in \(space.name). \(stays)"
        }
        let names = sharing.map(\.name).formatted(.list(type: .and))
        let all = sharing.count == 2 ? "both" : "all of them"
        return "\(names) share sign-ins, so this clears history in \(all). \(stays)"
    }
}
