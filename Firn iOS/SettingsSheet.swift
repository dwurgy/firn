import CloudKit
import FirnCore
import StoreKit
import SwiftUI

/// Settings on the iPhone, as iOS's own settings screens (David, 2026-11-19:
/// "native iOS, smooth and organized"): a navigation bar with Done, grouped
/// sections on the system background, and each space its own page.
///
/// - Spaces: every space in its order (hold and drag to reorder); a tap opens
///   its page (name, color, sign-ins, and Delete, in the Mac's words,
///   `Firn/SpacesSettings.swift`).
/// - Privacy: blocking's switch, and Clear History…. iCloud: sync's switch (docs/SYNC-PLAN.md).
/// - Tip Jar, last: the family's shared jar, its words unchanged.
///
/// Changes apply as they're made; only Stop Sharing and Delete ask first.
struct SettingsSheet: View {
    let store: BrowserStore
    let sync: ICloudSync

    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID] = []
    /// The saved switch, so it goes off by itself when the engine turns sync
    /// off (signed out of iCloud, another account, or Firn's data deleted).
    @AppStorage(ICloudSync.enabledKey) private var syncIsOn = false
    @State private var availability = ICloudSync.Availability.available
    @AppStorage(BrowserEngine.blockingKey) private var blocksContent = true
    @AppStorage(SearchSuggestions.preferenceKey) private var searchSuggestions = false
    @AppStorage(SearchEngine.preferenceKey) private var searchEngine = SearchEngine.default
    @Environment(TipJar.self) private var tipJar
    @Environment(\.purchase) private var purchase
    @Environment(\.openURL) private var openURL
    @Environment(\.showWelcome) private var showWelcome
    /// Send Feedback found no mail app to open its draft in.
    @State private var noMailApp = false
    @State private var clearingHistory = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                spacesSection
                searchSection
                privacySection
                syncSection
                defaultBrowserSection
                feedbackSection
                welcomeSection
                tipJarSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                        .tint(Theme.ink)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                SpaceSettingsPage(store: store, spaceID: id)
            }
        }
        // Ink, so no words are Glacier (David, 2026-11-23: tinted text is hard
        // to read): the picker's value, and the choices in iOS's questions.
        // Each switch takes its Glacier back by itself.
        .tint(Theme.ink)
        .presentationDetents([.large])
        .task { availability = await ICloudSync.availability() }
        // Signed in or out of iCloud while Settings is open.
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { availability = await ICloudSync.availability() }
        }
    }

    // MARK: Sections

    private var spacesSection: some View {
        Section {
            ForEach(store.spaces) { space in
                NavigationLink(value: space.id) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Theme.spaceColor(space.color))
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        Text(space.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(sharingLine(for: space))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityActions {
                    let index = store.spaces.firstIndex { $0.id == space.id } ?? 0
                    if index > 0 {
                        Button("Move Up") { move(space, by: -1) }
                    }
                    if index < store.spaces.count - 1 {
                        Button("Move Down") { move(space, by: 1) }
                    }
                }
            }
            .onMove { from, to in
                guard let index = from.first else { return }
                // `to` counts the row being moved; FirnCore's doesn't.
                store.moveSpace(store.spaces[index], to: to > index ? to - 1 : to)
            }
        } header: {
            Text("Spaces")
        } footer: {
            if store.spaces.count > 1 {
                Text("Hold a space and drag to change the order.")
            }
        }
    }

    /// "Search with" and "Show suggestions as you type", the Mac's choices
    /// in the Mac's words (Settings › General there), from the same list. Off until someone says yes: it's the one
    /// place typing goes over the network.
    private var searchSection: some View {
        Section {
            Picker("Search with", selection: $searchEngine) {
                ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
            }
            Toggle("Show suggestions as you type", isOn: $searchSuggestions)
                .tint(Theme.accent)
        } header: {
            Text("Search")
        } footer: {
            Text("With suggestions on, \(searchEngine.name) sees what you type.")
        }
    }

    /// "Block ads and trackers", the Mac's switch in the Mac's words
    /// (Settings › Privacy there). Pages follow from their next load.
    @ViewBuilder private var privacySection: some View {
        Section {
            Toggle("Block ads and trackers", isOn: $blocksContent)
                .tint(Theme.accent)
                .onChange(of: blocksContent) { BrowserEngine.setBlocking(enabled: blocksContent) }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Uses the EasyList and EasyPrivacy lists, which come with Firn. To let one site show its ads, open it and choose Stop Blocking from the page menu; each space keeps its own choices.")
        }
        // Where people look for it, as Safari's; the same question as
        // History's Clear, about the space on screen.
        Section {
            Button("Clear History…") { clearingHistory = true }
                .foregroundStyle(Theme.ink)
                .clearHistoryDialog(isPresented: $clearingHistory, store: store)
        }
    }

    /// "Sync with iCloud", the Mac's switch in the Mac's words. Only the
    /// one switch until passwords sync (step 9).
    private var syncSection: some View {
        let canSync = availability == .available
        return Section {
            Toggle("Sync with iCloud", isOn: Binding(
                get: { syncIsOn && canSync },
                set: { $0 ? sync.turnOn() : sync.turnOff() }
            ))
            .tint(Theme.accent)
            .disabled(!canSync)
            // What syncs is one tap away even when the switch can't be used
            // yet, so the choice is clear before signing in.
            NavigationLink("What Syncs") { WhatSyncsPage() }
        } header: {
            Text("iCloud")
        } footer: {
            switch availability {
            case .available: EmptyView()
            case .signedOut: Text("Sign in to iCloud in the Settings app to use sync.")
            case .unavailable: Text("iCloud isn’t available on this \(Self.device).")
            }
        }
    }

    static var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    /// The way to iOS's own choice: the default browser can only be picked
    /// in the Settings app, so this row opens Firn's page there. Firn can't
    /// say whether it's already the default (iOS lets an app ask only a few
    /// times a year), so the row never claims either way.
    private var defaultBrowserSection: some View {
        Section {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                HStack {
                    Text("Default Browser")
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.faint)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .accessibilityHint("Opens the Settings app")
        } footer: {
            Text("Opens Firn in the Settings app. Choose Default Browser App there, then Firn, so links from mail, chat, and other apps open here.")
        }
    }

    /// A blank email to David in the person's own mail app (`FeedbackEmail`),
    /// with only the versions and the model filled in. Firn sends nothing
    /// itself. With no mail app set up, the footer says where to write.
    private var feedbackSection: some View {
        Section {
            Button {
                openURL(FeedbackEmail.url) { opened in noMailApp = !opened }
            } label: {
                HStack {
                    Text("Send Feedback")
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.faint)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .accessibilityHint("Opens an email")
        } footer: {
            if noMailApp {
                Text("No mail app is set up on this \(Self.device). Write to \(FeedbackEmail.address) from anywhere.")
            } else {
                Text("Opens an email to \(FeedbackEmail.address) for bugs, ideas, or anything else. Firn fills in its version, the iOS version, and the \(Self.device) model; nothing is sent until you send it.")
            }
        }
    }

    /// The welcome again, as the Mac's Help › Show Welcome Again: it comes
    /// over Settings, which goes under it.
    private var welcomeSection: some View {
        Section {
            Button("Show Welcome Again") {
                showWelcome?()
                dismiss()
            }
            .foregroundStyle(Theme.ink)
        }
    }

    /// The tip jar (`TipJar.swift`): the family's line, then the three tips
    /// with the App Store's own prices; after a tip, the thank-you in their
    /// place. Last in Settings, and never shown anywhere unasked.
    private var tipJarSection: some View {
        Section {
            if tipJar.thanked {
                Text("Thank you. It really does help.")
            } else {
                switch tipJar.state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Loading tips")
                case .unavailable:
                    Text("Tips can’t be loaded right now.")
                        .foregroundStyle(.secondary)
                case .ready:
                    ForEach(tipJar.tips) { tip in
                        Button {
                            Task { await tipJar.buy(tip, with: purchase) }
                        } label: {
                            HStack {
                                Text(tip.displayName)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if tipJar.buying == tip.id {
                                    ProgressView()
                                } else {
                                    // The label's grey, not the button's tint.
                                    Text(tip.displayPrice)
                                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                                        .monospacedDigit()
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(tipJar.buying != nil)
                        .accessibilityLabel("\(tip.displayName), \(tip.displayPrice)")
                    }
                }
            }
        } header: {
            Text("Tip Jar")
        } footer: {
            if !tipJar.thanked {
                Text("Firn is made by one person. If it makes your day a little calmer, a tip helps keep it going.")
            }
        }
        .task { await tipJar.load() }
    }

    // MARK: Helpers

    private func move(_ space: Space, by step: Int) {
        guard let index = store.spaces.firstIndex(where: { $0.id == space.id }) else { return }
        withAnimation(.smooth(duration: 0.2)) {
            store.moveSpace(space, to: index + step)
        }
    }

    private func sharingLine(for space: Space) -> String {
        store.spacesSharingData(with: space).isEmpty ? "Separate" : "Shared"
    }
}

/// What sync carries and what stays on this device, in the Mac's words.
private struct WhatSyncsPage: View {
    var body: some View {
        List {
            ForEach(ICloudSync.whatSyncs(on: SettingsSheet.device), id: \.self) { line in
                Section { Text(line) }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("What Syncs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One space's page: its name, color, sign-ins, and Delete.
private struct SpaceSettingsPage: View {
    let store: BrowserStore
    let spaceID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The name as typed; the store keeps the last name that wasn't blank.
    @State private var name = ""
    @State private var confirmingStopSharing = false
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    private var space: Space? { store.spaces.first { $0.id == spaceID } }

    var body: some View {
        Group {
            if let space {
                form(space)
            } else {
                // Deleted while open: nothing to show, and Back is still there.
                Color.clear
            }
        }
        .navigationTitle(space?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = space?.name ?? "" }
    }

    private func form(_ space: Space) -> some View {
        let others = store.spacesSharingData(with: space)
        return List {
            Section {
                TextField(Space.defaultName, text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Name")
                    // The cursor and selection stay Glacier.
                    .tint(Theme.accent)
                    .onChange(of: name) {
                        if name.count > Space.nameLimit { name = String(name.prefix(Space.nameLimit)) }
                        store.updateSpace(space, name: name, color: space.color)
                    }
                    // A blank name isn't kept: the field shows the saved one again.
                    .onSubmit { name = self.space?.name ?? name }
                    .onChange(of: nameFocused) { if !nameFocused { name = self.space?.name ?? name } }
            } header: {
                Text("Name")
            }

            Section {
                SpaceSwatches(selection: Binding(
                    get: { self.space?.color ?? space.color },
                    set: { color in
                        guard let current = self.space else { return }
                        store.updateSpace(current, name: current.name, color: color)
                    }
                ))
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            } header: {
                Text("Color")
            }

            Section {
                Text(others.isEmpty
                     ? "Separate: its own sign-ins, cookies, and history."
                     : "Shared with \(names(others)).")
                    .fixedSize(horizontal: false, vertical: true)
                if !others.isEmpty {
                    Button("Stop Sharing…") { confirmingStopSharing = true }
                        .foregroundStyle(Theme.ink)
                }
            } header: {
                Text("Sign-ins")
            }

            if store.spaces.count > 1 {
                Section {
                    Button("Delete Space…", role: .destructive) { confirmingDelete = true }
                        .accessibilityLabel("Delete \(space.name)")
                } footer: {
                    // A separate space's sign-ins go too; shared ones stay.
                    Text(others.isEmpty
                         ? "Its tabs, groups, Basecamp, and sign-ins go with it."
                         : "Its tabs, groups, and Basecamp go with it.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog(
            "Stop sharing sign-ins?",
            isPresented: $confirmingStopSharing,
            titleVisibility: .visible
        ) {
            Button("Stop Sharing", role: .destructive) { store.stopSharing(space) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(space.name)” will start fresh, signed out of everything. \(names(others)) will stay signed in.")
        }
        .confirmationDialog(
            ICloudSync.isOn ? "Delete “\(space.name)” from all your devices?" : "Delete “\(space.name)”?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Space", role: .destructive) { delete(space) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage(for: space))
        }
    }

    private func delete(_ space: Space) {
        dismiss()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.deleteSpace(space) }
    }

    private func names(_ spaces: [Space]) -> String {
        spaces.map { "“\($0.name)”" }.formatted(.list(type: .and))
    }

    private func deleteMessage(for space: Space) -> String {
        let goes = "Its tabs, groups, and Basecamp will be deleted."
        if let other = store.spacesSharingData(with: space).first {
            return "\(goes) Its sign-ins stay, because “\(other.name)” still uses them."
        }
        return "\(goes) So will its sign-ins, cookies, and site data. This can’t be undone."
    }
}
