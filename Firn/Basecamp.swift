import FirnCore
import SwiftUI

/// Basecamp: the space's everyday sites as square tiles at the top of the
/// sidebar. Hidden while empty. Shows nothing but this space's own tiles.
struct BasecampGrid: View {
    let store: BrowserStore
    let window: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tile being dragged; nil when none is.
    @State private var drag: TileDrag?
    /// True while the pointer is down on a drag, so a drag the system
    /// cancels (no mouse-up) still ends.
    @GestureState private var dragging = false
    /// The grid's width, so a drag knows where each tile's slot is.
    @State private var width: CGFloat = 0
    /// Where the grid sits in the window, so a held tile never crosses its edge.
    @State private var originInWindow: CGPoint = .zero
    /// True once the lifted tile has risen (it grows a touch as it's picked up).
    @State private var raised = false
    /// The dragged tile's page, pictured in case it goes out over the page.
    @State private var preview: CGImage?

    /// Tiles glide aside at the same speed as tab rows do.
    private static let glide = Animation.smooth(duration: 0.2)
    private nonisolated static let space = "basecamp"

    var body: some View {
        // Measured even while empty, so a tab arriving knows where to go.
        VStack(spacing: 0) { grid }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named(BrowserWindow.space)).origin } action: {
                originInWindow = $0
            }
            .onChange(of: window.tabInBasecamp) { tabChanged(window.tabInBasecamp) }
            .onChange(of: window.tileArrival?.tab.id) {
                guard let id = window.tileArrival?.tab.id else { return }
                // A frame later, so the chip is drawn where the row was and rises from there.
                Task { @MainActor in arrive(id) }
            }
            .background {
                if window.tabInBasecamp?.released == false {
                    PointerWatch(window: window) { tabMoved(to: $0) }
                }
            }
    }

    @ViewBuilder private var grid: some View {
        let tiles = shownTiles
        if !tiles.isEmpty {
            BasecampFlow {
                ForEach(tiles) { tab in
                    if drag?.incoming == true, drag?.tab.id == tab.id {
                        // A tab arriving from the list: its slot waits open. In an
                        // empty Basecamp, it's a blank spot of frost (no words).
                        TileGlass().opacity(store.basecampTabs.isEmpty ? 1 : 0)
                    } else {
                        tile(tab)
                    }
                }
            }
            // A tab held up over a full Basecamp: no room opens, and a small
            // frost pill over the tiles says why (clear of the row tugging below).
            .overlay { fullHint }
            .overlay(alignment: .topLeading) { lifted }
            .coordinateSpace(.named(Self.space))
            // One drag for the whole grid, as in the tab list.
            .simultaneousGesture(dragGesture)
            .onChange(of: dragging) { if !dragging { drop() } }
            .padding(.bottom, Theme.sectionSpacing)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Basecamp")
        }
    }

    private var fullHint: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Text("Basecamp is full")
            .font(Theme.labelFont)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background { FrostGlass(shape: shape, color: Theme.spaceColor(store.activeSpace.color)) }
            .clipShape(shape)
            .opacity(window.basecampFullHint ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: window.basecampFullHint)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func tile(_ tab: FirnCore.Tab) -> some View {
        BasecampTile(tab: tab, isActive: tab.id == store.activeTabID) {
            store.select(tab)
            window.focusPage()
        } goHome: {
            store.goHome(tab)
            window.focusPage()
        } split: {
            window.pickSplit(beside: tab)
        } remove: {
            store.removeFromBasecamp(tab)
        } close: {
            window.closeTile(tab)
        }
        // While dragged, a tile holds its slot open; the lifted copy is
        // what shows (as a row, over the tab list, until it lands there).
        // Out over the page, the tile stays where it is.
        .opacity((drag?.tab.id == tab.id && drag?.place != .page)
                 || window.tileInList?.tab.id == tab.id
                 || window.tileArrival.map { $0.tab.id == tab.id && !$0.handedOver } == true ? 0 : 1)
    }

    /// A tab added from its menu (see `TabList.addToBasecamp`): its chip
    /// rises to just over the new tile's slot as the lifted tile a drag
    /// shows, then lands the way a dropped tile does: it settles into the
    /// slot, and only then does the glass tile take over.
    private func arrive(_ id: UUID, tries: Int = 3) {
        let tiles = store.basecampTabs
        let slots = slots(count: tiles.count)
        guard let index = tiles.firstIndex(where: { $0.id == id }), index < slots.count else {
            // The tab joins Basecamp a frame after its chip shows; wait for it a moment.
            if tries > 0, window.tileArrival?.tab.id == id {
                Task { @MainActor in arrive(id, tries: tries - 1) }
            } else {
                window.tileArrival = nil
            }
            return
        }
        window.tileArrival?.tile = CGRect(origin: inWindow(slots[index].origin), size: slots[index].size)
        withAnimation(.smooth(duration: 0.3)) {
            window.tileArrival?.landed = true
        } completion: {
            // As `drop()`: it settles into its slot, then the tile takes over.
            withAnimation(Self.glide) {
                window.tileArrival?.settled = true
            } completion: {
                withAnimation(Self.glide) {
                    window.tileArrival?.handedOver = true
                    window.tileArrival = nil
                }
            }
        }
    }

    /// The tiles as they'd be if the dragged one landed where it is now.
    private var shownTiles: [FirnCore.Tab] {
        var tiles = store.basecampTabs
        guard let drag else { return tiles }
        tiles.removeAll { $0.id == drag.tab.id }
        tiles.insert(drag.tab, at: min(drag.target, tiles.count))
        return tiles
    }

    /// Where each tile sits, in order. Reordering never changes the count,
    /// so these stay put while the tiles move between them.
    private var slots: [CGRect] { slots(count: tileCount(with: drag)) }

    /// The tiles, counting one arriving from the tab list.
    private func tileCount(with drag: TileDrag?) -> Int {
        store.basecampTabs.count + (drag?.incoming == true ? 1 : 0)
    }

    private func slots(count: Int) -> [CGRect] {
        let layout = BasecampLayout.make(count: count, width: width)
        return layout.rows.enumerated().flatMap { row, count in
            (0..<count).map { column in
                CGRect(x: CGFloat(column) * (layout.tileWidth + BasecampLayout.gap),
                       y: CGFloat(row) * (BasecampLayout.tileHeight + BasecampLayout.gap),
                       width: layout.tileWidth, height: BasecampLayout.tileHeight)
            }
        }
    }

    /// The lifted tile's top-left. It wants to stay in Basecamp (`Tug`),
    /// and never crosses the window's edge.
    private func position(of drag: TileDrag) -> CGPoint {
        let height = BasecampLayout.make(count: tileCount(with: drag), width: width).height
        let left = max(0, min(Tug.give, originInWindow.x - 2))
        return CGPoint(
            x: Tug.held(drag.location.x - drag.grab.width, 0, width - drag.size.width, give: left),
            y: Tug.held(drag.location.y - drag.grab.height, 0, height - drag.size.height))
    }

    /// The slot the lifted tile is over. It moves on only once the tile is
    /// clearly nearer another slot, so the tiles don't flicker back and forth.
    private func target(for drag: TileDrag) -> Int {
        let origin = position(of: drag)
        let middle = CGPoint(x: origin.x + drag.size.width / 2, y: origin.y + drag.size.height / 2)
        let distances = slots(count: tileCount(with: drag)).map { hypot($0.midX - middle.x, $0.midY - middle.y) }
        guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }) else { return drag.target }
        if drag.target < distances.count, distances[drag.target] - distances[nearest] < 12 { return drag.target }
        return nearest
    }

    /// The dragged tile, picked up: a solid sheet with a shadow under it.
    @ViewBuilder private var lifted: some View {
        if let drag {
            let origin = position(of: drag)
            liftedTile(drag.tab)
                .frame(width: drag.size.width, height: drag.size.height)
                .scaleEffect(raised && !reduceMotion ? 1.03 : 1)
                .animation(.smooth(duration: 0.15), value: raised)
                .offset(x: origin.x, y: origin.y)
                // It sticks to the pointer; only settling into place glides.
                .transaction { if !drag.settling { $0.animation = nil } }
                // Loose over the page (and on its way back), the window draws it (`TabLiftGhost`).
                .opacity(window.tabLift == nil ? 1 : 0)
                .onAppear { raised = true }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                guard var current = drag else {
                    // Only a drag that starts on a tile moves it.
                    let tiles = store.basecampTabs
                    guard let index = slots.firstIndex(where: { $0.contains(value.startLocation) }),
                          index < tiles.count else { return }
                    let slot = slots[index]
                    drag = TileDrag(
                        tab: tiles[index],
                        grab: CGSize(width: value.startLocation.x - slot.minX, height: value.startLocation.y - slot.minY),
                        size: slot.size, location: value.location, home: index, target: index)
                    window.isDraggingTab = true
                    window.dragPointer = inWindow(value.location)
                    picture(tiles[index])
                    return
                }
                guard !current.settling else { return }
                current.location = value.location
                window.dragPointer = inWindow(value.location)
                if comesLoose(&current) { return }
                follow(current)
            }
    }

    /// The held tile at its new place: the tiles make room where it'd land.
    private func follow(_ moved: TileDrag) {
        var current = moved
        if window.tabLift != nil { window.tabLift?.tile = heldInWindow(current) }
        let target = target(for: current)
        if target == current.target {
            drag = current
        } else {
            current.target = target
            withAnimation(reduceMotion ? nil : Self.glide) { drag = current }
        }
    }

    /// A tab dragged up out of the tab list (see `TabList.overBasecamp`):
    /// the tiles make room for it, and the window's lifted copy turns from
    /// its row into a tile. Taken back down, the room closes; let go, it
    /// settles into its slot and joins Basecamp there.
    private func tabChanged(_ arriving: TileInList?) {
        guard let arriving else {
            if drag?.incoming == true, drag?.settling == false {
                withAnimation(reduceMotion ? nil : Self.glide) { drag = nil }
                raised = false
            }
            return
        }
        if arriving.released {
            guard drag?.incoming == true else {
                // Nothing here to settle (it never got a slot): it simply goes back.
                window.tabInBasecamp = nil
                window.tabLift = nil
                return
            }
            return drop()
        }
        guard drag == nil, let lift = window.tabLift else { return }
        let count = store.basecampTabs.count
        let layout = BasecampLayout.make(count: count + 1, width: width)
        let size = CGSize(width: layout.tileWidth, height: BasecampLayout.tileHeight)
        var incoming = TileDrag(
            tab: arriving.tab, grab: CGSize(width: lift.grab.x * size.width, height: lift.grab.y * size.height),
            size: size, location: gridPoint(window.dragPointer), home: count, target: count, incoming: true)
        incoming.target = target(for: incoming)
        window.tabLift?.tileFace = AnyView(liftedTile(arriving.tab))
        window.tabLift?.tile = heldInWindow(incoming)
        withAnimation(reduceMotion ? nil : Self.glide) { drag = incoming }
        withAnimation(reshape) { window.tabLift?.isTile = true }
    }

    private func tabMoved(to pointer: CGPoint) {
        guard var current = drag, current.incoming, !current.settling else { return }
        current.location = gridPoint(pointer)
        follow(current)
    }

    /// A point in the window's space, in the grid's.
    private func gridPoint(_ pointer: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x - originInWindow.x, y: pointer.y - originInWindow.y)
    }

    /// A point in the grid's space, in the window's.
    private func inWindow(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x + originInWindow.x, y: location.y + originInWindow.y)
    }

    /// Where the lifted tile shows, in the window's space (grown a touch, as it's drawn).
    private func heldInWindow(_ drag: TileDrag) -> CGRect {
        let origin = inWindow(position(of: drag))
        let rect = CGRect(origin: origin, size: drag.size)
        guard !reduceMotion else { return rect }
        return rect.insetBy(dx: -rect.width * 0.015, dy: -rect.height * 0.015)
    }

    /// A tile that could open in split view gets a picture of its page
    /// taken as it's picked up; a resting tile is never woken for it.
    private func picture(_ tab: FirnCore.Tab) {
        preview = nil
        guard window.canDragOntoPage(tab), let page = tab.page else { return }
        Task {
            // Twice the card's width, so it's sharp on a Retina screen.
            let picture = await page.snapshot(width: Theme.liftedCard.width * 2)
            guard drag?.tab.id == tab.id else { return }
            preview = picture
            if window.tabLift?.tab.id == tab.id { window.tabLift?.preview = picture }
        }
    }

    /// Held in Basecamp, a tile comes loose once the pointer is out where
    /// it could go. Over a page where it could open in split view, it turns
    /// into the picture of its page and frost shows the half it would open
    /// in (a copy: the tile glides back to its slot and stays). Down over
    /// the tab list, it turns into a tab row and the list makes room for it;
    /// its slot here stays open until it lands, so nothing jumps under the
    /// pointer. Back over Basecamp, it's the tile again. True while it's loose.
    private func comesLoose(_ current: inout TileDrag) -> Bool {
        let side = window.pageSide(at: window.dragPointer, for: current.tab, past: originInWindow.x + width)
        let place: TilePlace = side != nil ? .page : overList(current) ? .list : .basecamp
        if place != current.place {
            move(&current, to: place)
        } else if place != .basecamp {
            drag = current
        }
        if let side {
            let drop = PageDrop(tab: current.tab, side: side)
            if window.pageDrop != drop { withAnimation(Theme.slide(reduceMotion: reduceMotion)) { window.pageDrop = drop } }
        }
        return place != .basecamp
    }

    /// Down past the gap below Basecamp, over the tab list. Going back takes
    /// a little less, so it doesn't flicker at the line.
    private func overList(_ current: TileDrag) -> Bool {
        let bottom = originInWindow.y + BasecampLayout.make(count: store.basecampTabs.count, width: width).height
        return window.dragPointer.y > bottom + Theme.sectionSpacing - (current.place == .list ? 8 : 0)
    }

    /// The held tile changing place, and shape with it.
    private func move(_ current: inout TileDrag, to place: TilePlace) {
        let from = current.place
        current.place = place
        if from == .page { withAnimation(Theme.slide(reduceMotion: reduceMotion)) { window.pageDrop = nil } }
        if from == .list { window.tileInList = nil }
        if place == .basecamp {
            drag = current
            window.tabLift?.tile = heldInWindow(current)
            let id = current.tab.id
            withAnimation(reshape) {
                shape(for: place)
            } completion: {
                // Still a tile on its way back: Basecamp's own copy takes over.
                if drag?.place == .basecamp, window.tabLift?.tab.id == id { window.tabLift = nil }
            }
            return
        }
        // Loose: the tiles go back as they were, its own slot waiting for it.
        current.target = current.home
        withAnimation(reduceMotion ? nil : Self.glide) { drag = current }
        if window.tabLift == nil {
            loosen(current)
            // Drawn as the tile first, so it can come loose from it.
            Task { @MainActor in
                guard drag?.place == place else { return }
                withAnimation(reshape) { shape(for: place) }
            }
        } else {
            withAnimation(reshape) { shape(for: place) }
        }
        if place == .list { window.tileInList = TileInList(tab: current.tab) }
    }

    private func shape(for place: TilePlace) {
        window.tabLift?.isCard = place == .page
        window.tabLift?.isTile = place == .basecamp
    }

    /// From here the window draws the held tile (`TabLiftGhost`), so it can
    /// leave Basecamp: as the tile at first, then as a row or a picture.
    private func loosen(_ current: TileDrag) {
        var lift = TabLift(tab: current.tab,
                           row: AnyView(TabRow(tab: current.tab, isActive: true, select: {}, close: {}) { EmptyView() }),
                           grab: CGPoint(x: current.grab.width / current.size.width,
                                         y: current.grab.height / current.size.height),
                           width: width, column: originInWindow.x)
        lift.tileFace = AnyView(liftedTile(current.tab))
        lift.tile = heldInWindow(current)
        lift.isTile = true
        lift.preview = preview
        window.tabLift = lift
    }

    /// The tile turning into its page's picture and back: a short glide; a fade with Reduce Motion.
    private var reshape: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.2)
    }

    private func liftedTile(_ tab: FirnCore.Tab) -> some View {
        BasecampTile(tab: tab, isActive: tab.id == store.activeTabID, lifted: true,
                     select: {}, goHome: {}, split: {}, remove: {}, close: {})
    }

    /// The lifted copy settles into its slot, then the tile really moves
    /// there (which looks like nothing, since it's already showing there).
    private func drop() {
        guard var current = drag, !current.settling else { return }
        window.isDraggingTab = false
        // Let go over the page: a copy opens there at once, its picture
        // fading as it does; the tile is already back in its slot.
        if current.place == .page {
            drag = nil
            raised = false
            preview = nil
            withAnimation(.easeOut(duration: 0.15)) { window.tabLift = nil }
            return window.dropOnPage()
        }
        // Let go over the tab list: it settles in there as a tab (see `TabList`),
        // and only then leaves Basecamp.
        if current.place == .list {
            drag = nil
            raised = false
            preview = nil
            window.tileInList?.released = true
            return
        }
        window.tabLift = nil
        preview = nil
        @MainActor func commit() {
            if current.incoming {
                // Its row's open slot in the tab list closes as it joins (see `TabList`).
                withAnimation(reduceMotion ? nil : Self.glide) {
                    store.addToBasecamp(current.tab, at: current.target)
                    drag = nil
                    window.tabInBasecamp = nil
                }
            } else if let tab = store.basecampTabs.first(where: { $0.id == current.tab.id }) {
                store.move(tab, to: current.target)
            }
            drag = nil
            raised = false
        }
        guard !reduceMotion, current.target < slots.count else { return commit() }
        let slot = slots[current.target]
        current.settling = true
        current.location = CGPoint(x: slot.minX + current.grab.width, y: slot.minY + current.grab.height)
        withAnimation(Self.glide) {
            drag = current
            raised = false
        } completion: {
            commit()
        }
    }
}

private struct TileDrag {
    let tab: FirnCore.Tab
    /// Where the pointer holds the tile, from its top-left.
    let grab: CGSize
    let size: CGSize
    /// The pointer, in the grid's space.
    var location: CGPoint
    /// Its place among the tiles when picked up.
    let home: Int
    /// Its place among the tiles.
    var target: Int
    var place = TilePlace.basecamp
    /// True while the lifted copy glides into its slot after the drop.
    var settling = false
    /// A tab from the tab list, not yet a tile (the list's drag moves it).
    var incoming = false
}

/// Where a held tile is: in Basecamp, or loose over the tab list or the page.
private enum TilePlace {
    case basecamp, list, page
}

/// Places tiles by `BasecampLayout`: balanced rows, the longest filling
/// the width, shorter rows starting at the left.
private struct BasecampFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 240
        let layout = BasecampLayout.make(count: subviews.count, width: width)
        return CGSize(width: width, height: layout.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = BasecampLayout.make(count: subviews.count, width: bounds.width)
        let size = ProposedViewSize(width: layout.tileWidth, height: BasecampLayout.tileHeight)
        var index = 0
        for (row, count) in layout.rows.enumerated() {
            for column in 0..<count {
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX + CGFloat(column) * (layout.tileWidth + BasecampLayout.gap),
                        y: bounds.minY + CGFloat(row) * (BasecampLayout.tileHeight + BasecampLayout.gap)),
                    proposal: size)
                index += 1
            }
        }
    }
}

private struct BasecampTile: View {
    let tab: FirnCore.Tab
    let isActive: Bool
    /// Picked up by a drag: solid, not glass, so it never turns see-through.
    var lifted = false
    let select: () -> Void
    let goHome: () -> Void
    let split: () -> Void
    let remove: () -> Void
    let close: () -> Void

    private var site: String { siteName(of: tab) }

    var body: some View {
        Button(action: select) {
            // Resting tiles (not loaded yet) look the same as loaded ones, as in
            // Dia: a faded tile reads as broken, or as a promise of a slow load.
            SiteMark(site: site, icon: tab.icon)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TileButtonStyle(isActive: isActive, lifted: lifted, accent: Theme.tileAccent(site: site, icon: tab.icon)))
        .help(tab.title)
        // Its speaker, while it makes sound, tucked in the corner.
        .overlay(alignment: .topTrailing) {
            SoundButton(tab: tab).padding(2)
        }
        .contextMenu {
            if tab.sound != .silent {
                MuteMenuItem(tab: tab)
                Divider()
            }
            if tab.isAwayFromHome {
                Button("Go Back to Home", action: goHome)
            }
            Button("Open as Split", action: split)
            Divider()
            Button("Remove from Basecamp", action: remove)
            Divider()
            Button("Close", action: close)
        }
        .accessibilityLabel(site.isEmpty ? tab.title : site)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// A tile's site, as its tile shows it: the home address's host, without "www.".
@MainActor private func siteName(of tab: FirnCore.Tab) -> String {
    let host = (tab.homeURL ?? tab.url)?.host(percentEncoded: false) ?? ""
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

/// A tab added to Basecamp from its menu, on its way up: where its row
/// was, and its tile's slot once Basecamp has made room (window space).
struct TileArrival {
    let tab: FirnCore.Tab
    /// The tab on screen, so its lifted tile looks chosen, as a dragged one does.
    let isActive: Bool
    let row: CGRect
    var tile: CGRect?
    /// Up over its slot, lifted (this is what the trip animates).
    var landed = false
    /// Down in its slot, as a dropped tile settles.
    var settled = false
    /// The tile itself shows now; the chip fades off it.
    var handedOver = false
}

/// The trip up into Basecamp (`TileArrival`). The row's title goes at
/// once, so no squashed half-row ever shows: what travels is the site's
/// icon on a small chip, which grows into the lifted tile a drag shows
/// (a touch larger than the slot), its icon gliding from the row's
/// leading edge to the tile's middle. Then it settles like a dropped tile.
struct TileArrivalChip: View {
    let window: WindowModel

    var body: some View {
        if let arrival = window.tileArrival {
            ArrivalFlight(arrival: arrival, progress: arrival.landed ? 1 : 0, settled: arrival.settled ? 1 : 0)
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct ArrivalFlight: View, Animatable {
    let arrival: TileArrival
    /// 0 where the row was, 1 lifted over the tile's slot.
    var progress: CGFloat
    /// 0 lifted, 1 down in the slot.
    var settled: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, settled) }
        set {
            progress = newValue.first
            settled = newValue.second
        }
    }

    var body: some View {
        let slot = arrival.tile ?? arrival.row
        // Lifted, it's a touch larger than its slot, as a dragged tile is (`heldInWindow`).
        let grown = (1 - settled) * 0.015
        let to = slot.insetBy(dx: -slot.width * grown, dy: -slot.height * grown)
        let from = arrival.row
        let frame = CGRect(x: from.minX + (to.minX - from.minX) * progress,
                           y: from.minY + (to.minY - from.minY) * progress,
                           width: from.width + (to.width - from.width) * progress,
                           height: from.height + (to.height - from.height) * progress)
        let shape = RoundedRectangle(cornerRadius: Theme.tabRadius + (Theme.tileRadius - Theme.tabRadius) * progress,
                                     style: .continuous)
        // The row's icon sits 8pt into its padding (16pt wide), centered on the row's height.
        let rowIcon = CGPoint(x: Theme.rowPadding + 8, y: Theme.rowHeight / 2)
        let icon = CGPoint(x: rowIcon.x + (frame.width / 2 - rowIcon.x) * progress,
                           y: rowIcon.y + (frame.height / 2 - rowIcon.y) * progress)
        ZStack(alignment: .topLeading) {
            Text(arrival.tab.title)
                .font(Theme.tabFont)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                // Cut off where the row's was.
                .frame(width: max(0, arrival.row.width - Theme.rowPadding * 2 - 24),
                       height: Theme.rowHeight, alignment: .leading)
                .offset(x: Theme.rowPadding + 24)
                .opacity(max(0, 1 - progress * 5))
            // 16pt in the row, 18pt on the tile.
            SiteMark(site: siteName(of: arrival.tab), icon: arrival.tab.icon)
                .scaleEffect((16 + 2 * progress) / 18)
                .position(icon)
            // Over the second half of the trip, it becomes the lifted tile a drag shows.
            BasecampTile(tab: arrival.tab, isActive: arrival.isActive, lifted: true,
                         select: {}, goHome: {}, split: {}, remove: {}, close: {})
                .frame(width: frame.width, height: frame.height)
                .opacity(min(1, max(0, progress * 2 - 1)))
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .background {
            LiftBacking(shape: shape)
                .overlay {
                    // The tab on screen leaves as its row did, a sheet, which
                    // fades over the first half as the tile's ice comes in.
                    if arrival.isActive {
                        shape.fill(Theme.activeTab)
                            .overlay { shape.strokeBorder(Theme.activeTabHairline, lineWidth: 0.5) }
                            .opacity(max(0, 1 - progress * 2))
                    }
                }
        }
        .clipShape(shape)
        .shadow(color: Theme.shadowPageFar, radius: 8, y: 3)
        .offset(x: frame.minX, y: frame.minY)
    }
}

/// The site's own icon, or until it's found (or if the site has none), a
/// soft rounded square in a calm color with the site's first letter.
struct SiteMark: View {
    let site: String
    let icon: Data?

    var body: some View {
        SiteIconView(icon: icon, size: 18) { letterMark }
    }

    private var letterMark: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Theme.siteColor(for: site).gradient)
            .frame(width: 18, height: 18)
            .overlay {
                Text(site.first.map { String($0).uppercased() } ?? "")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .accessibilityHidden(true)
    }
}

/// A tile of frosted ice: Liquid Glass with a cool snowy tint and a crisp
/// edge on macOS 26 and later, a frosted fill and lit rim before it.
/// Brighter on hover, a gentle press. The chosen tile keeps its glass and
/// takes the colors of the site's icon: a soft wash, a ring of colored glass
/// that follows where each color sits in the icon, and a faint glow.
private struct TileButtonStyle: ButtonStyle {
    let isActive: Bool
    let lifted: Bool
    let accent: Theme.TileAccent
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
    }

    private var dark: Bool { colorScheme == .dark }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isActive { chosen } else { resting }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hovering)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isActive)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: accent)
            .onHover { hovering = $0 }
    }

    /// The page on screen: the same glass, washed in the icon's main color
    /// (stronger at the top, like light through ice), ringed in its colors.
    private var chosen: some View {
        resting
            .overlay {
                shape.fill(LinearGradient(
                    colors: [accent.main.opacity(dark ? 0.18 : 0.2), accent.main.opacity(dark ? 0.12 : 0.07)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                // AngularGradient starts at 3 o'clock and runs clockwise, as the ring does.
                shape.strokeBorder(
                    AngularGradient(colors: accent.ring + accent.ring.prefix(1), center: .center),
                    lineWidth: Theme.tileRingWidth)
                    .opacity(reduceTransparency ? 1 : (dark ? 0.95 : 0.9))
            }
            .overlay {
                // Light catching the ring's outer edge along the top, gone by
                // the middle: a thin line, so the color underneath stays full.
                shape.strokeBorder(
                    LinearGradient(colors: [Theme.tileRingSheen, Theme.tileRingSheen.opacity(0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1)
            }
            .shadow(color: accent.main.opacity(dark ? 0.18 : 0.28), radius: 5)
    }

    @ViewBuilder private var resting: some View {
        if lifted {
            // The same ice as at rest, over the frame so it stays frost over
            // the page, with a wider shadow beneath it.
            TileGlass()
                .background { LiftBacking(shape: shape) }
                .shadow(color: Theme.shadowPageFar, radius: 9, y: 4)
        } else {
            TileGlass(hovering: hovering)
        }
    }
}

/// A tile's frosted ice, with nothing on it: under every resting tile, and
/// alone as the spot an empty Basecamp shows while a tab is held over it.
private struct TileGlass: View {
    var hovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
    }

    var body: some View {
        if reduceTransparency {
            shape.fill(Theme.tileSolid)
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5) }
        } else {
            // Frosted fills, not Liquid Glass: the window is already glass, and
            // glass on glass turns muddy. The tile reads as etched into the frame.
            shape.fill(hovering ? Theme.tileFillHover : Theme.tileFill)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Theme.tileRimTop, Theme.tileRimBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .overlay { shape.strokeBorder(Theme.tileHairline, lineWidth: 0.5).padding(-0.5) }
                .shadow(color: Theme.shadowSoft, radius: 1, y: 0.5)
        }
    }
}
