import FirnCore
import SwiftUI

// History on the iPhone (docs/IOS-PLAN.md, section 12): the Mac's History
// window (`Firn/HistoryWindow.swift`) as one of iOS's own sheets, from the
// page menu and the command bar. Only the space on screen's history (each
// space is its own browser); spaces sharing sign-ins share it.

extension EnvironmentValues {
    /// Opens the History sheet (`BrowserScreen` shows it): the page menu's
    /// History row and the command bar's.
    @Entry var showHistory: SheetAction? = nil
}

/// History, as iOS's own list (docs/IOS-PLAN.md, section 9's look): a
/// grouped list on iOS's neutral background, as Downloads and Settings, never
/// washed in the space's color. The space's visits, newest first, a section
/// per day, with a search field. A tap opens a visit as a new tab; a swipe
/// left deletes it, and holding it gives iOS's menu (Copy Link, Delete, and
/// Delete All from its site). Clear, in the top bar, asks how far back.
///
/// Visits are read a page at a time as the list scrolls, as on the Mac.
struct HistorySheet: View {
    let store: BrowserStore
    /// Opens a visit as a new tab and puts this sheet away.
    let open: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var search = ""
    @State private var visits: [HistoryVisit] = []
    @State private var days: [Day] = []
    @State private var loaded = false
    @State private var reachedEnd = false
    @State private var loadingMore = false
    @State private var icons: [String: Data] = [:]
    @State private var clearing = false

    /// One day's visits, under its heading.
    private struct Day: Identifiable {
        let start: Date
        let visits: [HistoryVisit]
        var id: Date { start }
    }

    private var space: Space { store.activeSpace }

    /// What's read: new words start over.
    private var readKey: String { "\(space.dataStoreID)\n\(search)" }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(days) { day in
                    Section(heading(for: day.start)) {
                        ForEach(day.visits) { visit in
                            row(visit)
                                .onAppear { if visit.id == visits.last?.id { readMore() } }
                        }
                    }
                }
                if reachedEnd, !visits.isEmpty, !isSearching {
                    Section {} footer: { Text("History is kept for a year.") }
                }
            }
            .listStyle(.insetGrouped)
            .overlay { emptyMessage }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search History")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { clearing = true }
                        .tint(Theme.ink)
                        .disabled(loaded && visits.isEmpty && !isSearching)
                        .accessibilityLabel("Clear History")
                        .clearHistoryDialog(isPresented: $clearing, store: store) {
                            Task { await readFirstPage() }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                        .tint(Theme.ink)
                }
            }
        }
        .tint(Theme.ink)
        .presentationDetents([.large])
        .task(id: readKey) { await readFirstPage() }
    }

    // MARK: Parts

    /// The Mac's words (`Firn/HistoryWindow.swift`), in iOS's own empty look.
    @ViewBuilder private var emptyMessage: some View {
        if loaded && visits.isEmpty {
            if isSearching {
                ContentUnavailableView(
                    "No results", systemImage: "magnifyingglass",
                    description: Text("Nothing in \(space.name)'s history matches \u{201C}\(search.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}.")
                )
            } else {
                ContentUnavailableView(
                    "No history yet", systemImage: "clock",
                    description: Text("Pages you visit in \(space.name) appear here.")
                )
            }
        }
    }

    /// One visit: the site's icon, the page's title over its site, and the
    /// time. A tap opens it as a new tab.
    private func row(_ visit: HistoryVisit) -> some View {
        Button {
            // Only web addresses, whatever the file holds.
            guard WebAddress.isWebURL(visit.url) else { return }
            open(visit.url)
        } label: {
            HStack(spacing: 12) {
                SiteIconView(icon: icons[visit.url.host(percentEncoded: false)?.lowercased() ?? ""], size: 24) {
                    LetterMark(site: visit.site)
                }
                VStack(alignment: .leading, spacing: 2) {
                    // `Color`, not `.primary`: inside a list's button the
                    // style would follow the tint.
                    Text(visit.title.isEmpty ? visit.site : visit.title)
                        .foregroundStyle(Color.primary)
                    Text(visit.site)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(visit.visitedAt.formatted(date: .omitted, time: .shortened))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens in a new tab")
        .contextMenu {
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.url = visit.url }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { delete(visit) }
            Button("Delete All from \(visit.site)", systemImage: "trash", role: .destructive) {
                deleteAll(from: visit.site)
            }
        }
        .swipeActions(edge: .trailing) {
            // iOS's red, said outright: the sheet's ink tint would take it.
            Button("Delete", systemImage: "trash", role: .destructive) { delete(visit) }
                .tint(.red)
        }
    }

    /// "Today", "Yesterday", or the date ("Thursday, October 22"; the year
    /// only when it isn't this one), as on the Mac.
    private func heading(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        let style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        return day.formatted(sameYear ? style : style.year())
    }

    // MARK: Reading

    /// The newest visits, starting the list over.
    private func readFirstPage() async {
        let fresh = await store.historyVisits(in: space, matching: search)
        guard !Task.isCancelled else { return }
        reachedEnd = fresh.count < BrowserStore.historyPageSize
        show(fresh)
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

    // MARK: Deleting

    /// Deletes the visit at once (no asking: it's only history, and Safari
    /// doesn't ask either, nor the Mac); its row leaves the list.
    private func delete(_ visit: HistoryVisit) {
        let space = space
        removeRows { $0.id == visit.id }
        Task { await store.deleteHistory(visits: [visit.id], in: space) }
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
    }

    /// Site icons from this history's own tabs, where there are any (history
    /// keeps no icons of its own), as on the Mac.
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
}

// MARK: - Clear History

extension View {
    /// Clear History…: iOS's own question, how far back to clear, in the
    /// Mac's four ranges and words (`HistoryClearRange`), saying whose history
    /// it is (spaces sharing sign-ins share it). Asked from History's Clear
    /// and from Settings › Privacy, about the space on screen. `cleared` runs
    /// once the visits are gone.
    func clearHistoryDialog(
        isPresented: Binding<Bool>, store: BrowserStore, cleared: @escaping () -> Void = {}
    ) -> some View {
        // iOS colors the choices from the sheet's own tint: ink in History,
        // Glacier in Settings (as its "Search with" picker).
        confirmationDialog("Clear history", isPresented: isPresented, titleVisibility: .visible) {
            ForEach(HistoryClearRange.allCases) { range in
                Button(range.title) {
                    let space = store.activeSpace
                    Task {
                        await store.clearHistory(range, in: space)
                        cleared()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.clearHistoryExplanation(for: store.activeSpace))
        }
    }
}
