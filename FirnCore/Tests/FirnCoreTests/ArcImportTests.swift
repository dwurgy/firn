import Foundation
import Testing
@testable import FirnCore

/// Builds a hand-made `StorableSidebar.json` the way Arc lays it out: lists
/// that alternate an id and its record.
private struct ArcFile {
    var items: [Any] = []
    var spaces: [Any] = []
    var topApps: [Any] = []

    @discardableResult
    mutating func tab(_ id: String, _ url: String, title: String = "Saved", renamed: String? = nil, parent: String?) -> String {
        var item: [String: Any] = [
            "id": id, "childrenIds": [String](),
            "data": ["tab": ["savedURL": url, "savedTitle": title]],
        ]
        item["parentID"] = parent ?? NSNull()
        item["title"] = renamed ?? NSNull()
        items += [id, item]
        return id
    }

    @discardableResult
    mutating func folder(_ id: String, _ title: String?, children: [String], parent: String?) -> String {
        items += [id, [
            "id": id, "title": title ?? NSNull(), "parentID": parent ?? NSNull(), "childrenIds": children,
            "data": ["list": [String: Any]()],
        ] as [String: Any]]
        return id
    }

    mutating func container(_ id: String, children: [String], topApps: Bool = false) {
        let type = topApps ? "topApps" : "spaceItems"
        items += [id, [
            "id": id, "title": NSNull(), "parentID": NSNull(), "childrenIds": children,
            "data": ["itemContainer": ["containerType": [type: ["_0": "x"]]]],
        ] as [String: Any]]
    }

    mutating func space(_ id: String, _ title: String, profile: Any = ["default": true], pinned: String) {
        spaces += [id, [
            "id": id, "title": title, "profile": profile, "customInfo": ["iconType": ["emoji_v2": "🙂"]],
            "containerIDs": ["unpinned", "\(id)-unpinned", "pinned", pinned],
        ] as [String: Any]]
    }

    var data: Data {
        let root: [String: Any] = [
            "version": 1,
            "sidebar": ["containers": [
                ["global": [String: Any]()],
                ["spaces": spaces, "items": items, "topAppsContainerIDs": topApps],
            ]],
        ]
        return try! JSONSerialization.data(withJSONObject: root)
    }
}

private var workProfile: [String: Any] { ["custom": ["_0": ["directoryBasename": "Profile 1"]]] }

struct ArcImportPlanTests {
    @Test func foldersBecomeGroupsAndLooseTabsBecomePinned() throws {
        var file = ArcFile()
        file.tab("t1", "https://news.example/", title: "News", parent: "pinned")
        file.tab("t2", "https://a.example/", parent: "f1")
        file.tab("t3", "https://b.example/", parent: "f2")
        file.folder("f2", "Inner", children: ["t3"], parent: "f1")
        file.folder("f1", "Reading", children: ["t2", "f2"], parent: "pinned")
        file.tab("t4", "https://c.example/", renamed: "My C", parent: "pinned")
        file.container("pinned", children: ["t1", "f1", "t4"])
        file.space("s1", "Home", pinned: "pinned")

        let plan = try ArcImportPlan(file.data)
        let space = try #require(plan.spaces.first)
        #expect(space.name == "Home")
        #expect(space.basecamp.isEmpty)
        #expect(space.groups.map(\.name) == ["Pinned", "Reading"])
        #expect(space.groups[0].sites.map(\.title) == ["News", "My C"])
        // The nested folder is flattened into its top folder.
        #expect(space.groups[1].sites.map(\.url.host) == ["a.example", "b.example"])
        #expect(plan.tabCount == 4)
    }

    @Test func unpinnedTabsStayBehind() throws {
        var file = ArcFile()
        file.tab("t1", "https://kept.example/", parent: "pinned")
        file.container("pinned", children: ["t1"])
        file.tab("t2", "https://left.example/", parent: "s1-unpinned")
        file.container("s1-unpinned", children: ["t2"])
        file.space("s1", "Home", pinned: "pinned")

        let plan = try ArcImportPlan(file.data)
        #expect(plan.spaces[0].groups.flatMap(\.sites).map(\.url.host) == ["kept.example"])
    }

    @Test func favoritesFollowTheProfileAndOverflowIntoAGroup() throws {
        var file = ArcFile()
        let personalFavorites = (1...14).map { file.tab("p\($0)", "https://site\($0).example/", parent: "top-default") }
        file.container("top-default", children: personalFavorites, topApps: true)
        file.tab("w1", "https://work.example/", parent: "top-work")
        file.container("top-work", children: ["w1"], topApps: true)
        file.topApps = [["default": true], "top-default", workProfile, "top-work"]
        file.tab("t1", "https://pinned.example/", parent: "pin1")
        file.container("pin1", children: ["t1"])
        file.container("pin2", children: [])
        file.container("pin3", children: [])
        file.space("s1", "Personal", pinned: "pin1")
        file.space("s2", "Work", profile: workProfile, pinned: "pin2")
        file.space("s3", "Also Personal", pinned: "pin3")

        let plan = try ArcImportPlan(file.data)
        #expect(plan.spaces.map(\.name) == ["Personal", "Work", "Also Personal"])
        #expect(plan.profileCount == 2)
        #expect(plan.sharingSignIns == [["Personal", "Also Personal"]])
        let personal = plan.spaces[0]
        #expect(personal.basecamp.count == 12)
        #expect(personal.groups.map(\.name) == ["Favorites", "Pinned"])
        #expect(personal.groups[0].sites.map(\.url.host) == ["site13.example", "site14.example"])
        #expect(plan.spaces[1].basecamp.map(\.url.host) == ["work.example"])
        // Same profile, same favorites, copied into each space.
        #expect(plan.spaces[2].basecamp == personal.basecamp)
    }

    @Test func onlyWebAddressesComeOverAndOthersAreCountedOnce() throws {
        var file = ArcFile()
        file.tab("f1", "file:///Users/someone/secret.pdf", parent: "top")
        file.tab("f2", "arc://settings", parent: "top")
        file.tab("f3", "https://ok.example/", parent: "top")
        file.container("top", children: ["f1", "f2", "f3"], topApps: true)
        file.topApps = [["default": true], "top"]
        file.tab("t1", "javascript:alert(1)", parent: "pin")
        file.tab("t2", "not a url at all", parent: "pin")
        file.tab("t3", "http://plain.example/" + String(repeating: "a", count: 3000), parent: "pin")
        file.container("pin", children: ["t1", "t2", "t3"])
        file.container("pin2", children: [])
        file.space("s1", "One", pinned: "pin")
        file.space("s2", "Two", pinned: "pin2")

        let plan = try ArcImportPlan(file.data)
        #expect(plan.spaces[0].basecamp.map(\.url.host) == ["ok.example"])
        #expect(plan.spaces[0].groups.isEmpty)
        #expect(plan.skipped == 5)
    }

    @Test func loopsAndMissingIdsAreWalkedSafely() throws {
        var file = ArcFile()
        file.tab("t1", "https://a.example/", parent: "f1")
        file.folder("f1", "Loop", children: ["t1", "f2", "missing"], parent: "pin")
        file.folder("f2", "Back", children: ["f1", "t1"], parent: "f1")
        file.container("pin", children: ["f1", "nowhere"])
        file.space("s1", "Home", pinned: "pin")

        let plan = try ArcImportPlan(file.data)
        #expect(plan.spaces[0].groups.map(\.name) == ["Loop"])
        #expect(plan.spaces[0].groups[0].sites.map(\.url.host) == ["a.example"])
    }

    @Test func namesAreCleanedAndEmptyFoldersLeftOut() throws {
        var file = ArcFile()
        file.tab("t1", "https://a.example/", title: "Line\none", parent: "f1")
        file.folder("f1", "  \n ", children: ["t1"], parent: "pin")
        file.folder("f2", "Empty", children: [], parent: "pin")
        file.container("pin", children: ["f1", "f2"])
        file.space("s1", String(repeating: "x", count: 300), pinned: "pin")

        let plan = try ArcImportPlan(file.data)
        #expect(plan.spaces[0].name.count == TabGroup.nameLimit)
        #expect(plan.spaces[0].groups.map(\.name) == [TabGroup.defaultName])
        #expect(plan.spaces[0].groups[0].sites[0].title == "Line one")
    }

    @Test func aDamagedOrForeignFileIsRefused() {
        #expect(throws: ArcImportError.damaged) { try ArcImportPlan(Data("{\"sidebar\":".utf8)) }
        #expect(throws: ArcImportError.notRecognized) { try ArcImportPlan(Data("[1, 2, 3]".utf8)) }
        #expect(throws: ArcImportError.notRecognized) { try ArcImportPlan(ArcFile().data) }
        #expect(throws: ArcImportError.tooLarge) {
            try ArcImportPlan(Data(count: ArcImportPlan.sizeLimit + 1))
        }
    }
}

@MainActor
struct ArcImportStoreTests {
    private let personal = Space(name: "Personal", icon: "leaf", color: "glacier", order: 0, dataStoreID: UUID())

    @Test func importAddsSpacesWithTheirOwnTilesGroupsAndSignIns() throws {
        var file = ArcFile()
        file.tab("p1", "https://mail.example/", title: "Mail", parent: "top")
        file.container("top", children: ["p1"], topApps: true)
        file.topApps = [["default": true], "top"]
        file.tab("t1", "https://docs.example/", parent: "f1")
        file.folder("f1", "Docs", children: ["t1"], parent: "pin1")
        file.container("pin1", children: ["f1"])
        file.container("pin2", children: [])
        file.container("pin3", children: [])
        file.space("s1", "Home", pinned: "pin1")
        file.space("s2", "Work", profile: workProfile, pinned: "pin2")
        file.space("s3", "Home Two", pinned: "pin3")
        let plan = try ArcImportPlan(file.data)

        let store = BrowserStore(spaces: [personal], makePage: { FakePage(dataStoreID: $0) })
        store.openTab(URL(string: "https://already.example/")!)
        let colors = ["glacier", "sand", "sage", "heather"]
        let added = store.importFromArc(plan) { existing in
            ("icon\(existing.count)", colors.first { c in !existing.contains { $0.color == c } }!)
        }

        #expect(store.spaces.map(\.name) == ["Personal", "Home", "Work", "Home Two"])
        #expect(store.spaces.map(\.order) == [0, 1, 2, 3])
        #expect(store.activeSpaceID == personal.id)
        #expect(store.openTabs.count == 1)
        // Same Arc profile, same sign-ins; never the existing space's.
        #expect(added[0].dataStoreID == added[2].dataStoreID)
        #expect(added[0].dataStoreID != added[1].dataStoreID)
        #expect(!added.contains { $0.dataStoreID == personal.dataStoreID })
        // Each picks the next free style, counting the spaces added before it.
        #expect(added.map(\.color) == ["sand", "sage", "heather"])
        #expect(added.map(\.icon) == ["icon1", "icon2", "icon3"])

        store.selectSpace(added[0])
        let tile = try #require(store.basecampTabs.first)
        #expect(tile.homeURL == URL(string: "https://mail.example/"))
        #expect(tile.title == "Mail")
        #expect(tile.isResting)
        #expect(store.tabGroups.map(\.name) == ["Docs"])
        #expect(store.tabs(in: store.tabGroups[0]).map(\.url?.host) == ["docs.example"])
        #expect(store.tabs(in: store.tabGroups[0]).allSatisfy { $0.isResting })

        store.selectSpace(added[2])
        #expect(store.basecampTabs.map(\.homeURL?.host) == ["mail.example"])
        #expect(store.tabGroups.isEmpty)
    }

    @Test func importedSpacesSurviveQuitAndReopen() throws {
        var file = ArcFile()
        file.tab("t1", "https://docs.example/", parent: "pin")
        file.container("pin", children: ["t1"])
        file.space("s1", "Home", pinned: "pin")
        let store = BrowserStore(spaces: [personal], makePage: { FakePage(dataStoreID: $0) })
        store.importFromArc(try ArcImportPlan(file.data)) { _ in ("leaf", "sand") }

        let restored = BrowserStore(
            restoring: store.session(sidebarWidth: 260, sidebarCollapsed: false),
            defaultSpaces: [personal], makePage: { FakePage(dataStoreID: $0) }
        )
        // The untouched first space was replaced, and stays replaced.
        #expect(restored.spaces.map(\.name) == ["Home"])
        #expect(restored.tabGroups.map(\.name) == ["Pinned"])
        #expect(restored.tabs(in: restored.tabGroups[0]).map(\.url?.host) == ["docs.example"])
    }

    @Test func importReplacesTheUntouchedFirstSpace() throws {
        var file = ArcFile()
        file.tab("t1", "https://docs.example/", parent: "pin1")
        file.container("pin1", children: ["t1"])
        file.container("pin2", children: [])
        file.space("s1", "Home", pinned: "pin1")
        file.space("s2", "Work", profile: workProfile, pinned: "pin2")
        let plan = try ArcImportPlan(file.data)

        var removed: [UUID] = []
        let store = BrowserStore(
            spaces: [personal], makePage: { FakePage(dataStoreID: $0) }, removeData: { removed.append($0) }
        )
        #expect(store.hasOnlyUntouchedSpace)
        var seen: [[String]] = []
        let added = store.importFromArc(plan) { existing in
            seen.append(existing.map(\.name))
            return ("leaf", "sand")
        }

        #expect(store.spaces.map(\.name) == ["Home", "Work"])
        #expect(store.spaces.map(\.order) == [0, 1])
        #expect(store.activeSpaceID == added[0].id)
        #expect(store.tabGroups.map(\.name) == ["Pinned"])
        // Styles are picked as if the old space were never there.
        #expect(seen == [[], ["Home"]])
        #expect(removed == [personal.dataStoreID])
        #expect(!store.hasOnlyUntouchedSpace)
    }

    @Test func importLeavesAnUsedOrSecondSpaceAlone() throws {
        var file = ArcFile()
        file.container("pin", children: [])
        file.space("s1", "Home", pinned: "pin")
        let plan = try ArcImportPlan(file.data)

        // A tab in a group: the space was used.
        let grouped = BrowserStore(spaces: [personal], makePage: { FakePage(dataStoreID: $0) })
        grouped.openTab(URL(string: "https://already.example/")!)
        _ = grouped.newGroup(with: grouped.openTabs[0])
        #expect(!grouped.hasOnlyUntouchedSpace)
        grouped.importFromArc(plan) { _ in ("leaf", "sand") }
        #expect(grouped.spaces.map(\.name) == ["Personal", "Home"])

        // Two empty spaces: someone made the second, so nothing is replaced.
        let work = Space(name: "Work", icon: "leaf", color: "sand", order: 1, dataStoreID: UUID())
        let two = BrowserStore(spaces: [personal, work], makePage: { FakePage(dataStoreID: $0) })
        #expect(!two.hasOnlyUntouchedSpace)
        two.importFromArc(plan) { _ in ("leaf", "sage") }
        #expect(two.spaces.map(\.name) == ["Personal", "Work", "Home"])
        #expect(two.activeSpaceID == personal.id)
    }
}
