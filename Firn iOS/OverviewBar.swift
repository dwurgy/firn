import FirnCore
import SwiftUI

/// The overview's bar, balanced like Safari's: + on the left, the space's
/// name in a frosted pill in the middle, and a round check on the right in
/// a vivid version of the space's color. All on Firn's frost (`BarFrost`),
/// over the list's soft edge blur; pressed, the warm wash.
///
/// The pill is the space switcher (phase 4, step 1): a dot per space under
/// the name, as on the Mac; a tap opens the space menu; a sideways swipe on
/// it changes space with the address bar's sliding pills (`BarSlide`; David,
/// 2026-11-13: the same movement as swiping between tabs).
struct OverviewBar: View {
    let space: Space
    let spaces: [Space]
    let newTab: () -> Void
    let done: () -> Void
    /// A tap on the pill: the space menu, beside the pill (global frame).
    let openMenu: (CGRect) -> Void
    let select: (Space) -> Void

    /// Back's and the tabs button's size, so + and the check sit exactly
    /// where they were.
    private static let height = BarButton.glassSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the pill has slid toward the next space, as the address
    /// bar's: positive to the right (the space before coming in from +'s
    /// side). Only where there's a space to come in.
    @State private var progress: CGFloat = 0
    /// Let go past the middle: the pills finish the slide, then it changes.
    @State private var finishing = false
    @State private var pillFrame: CGRect = .zero
    /// The arriving space's name, fading in once its pill is whole (as the
    /// next tab's words do on the address bar), rather than cross-fading
    /// out of the old one.
    @State private var wordsIn: Double = 1
    /// True while a finger is on the pill. A swipe iOS cancels never
    /// reports its end, so the pills settle back when this goes false.
    @GestureState private var touching = false

    private var index: Int { spaces.firstIndex { $0.id == space.id } ?? 0 }

    /// The space a slide this way brings in, if any (no wrapping: the ends
    /// hold still, as the address bar's last tab does).
    private func neighbor(_ direction: CGFloat) -> Space? {
        let next = index + (direction > 0 ? -1 : 1)
        return spaces.indices.contains(next) ? spaces[next] : nil
    }

    private var slide: BarSlide? { progress == 0 ? nil : BarSlide(progress: progress) }

    var body: some View {
        ZStack {
            pill
                .padding(.horizontal, Self.height + 16)
            HStack {
                Button(action: newTab) {
                    Image(systemName: "plus")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(Theme.ink)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(FrostPress(shape: Circle()))
                .background { BarFrost(shape: Circle(), space: space.color) }
                .accessibilityLabel("New Tab")
                Spacer()
                Button(action: done) {
                    Image(systemName: "checkmark")
                        .font(BarButton.symbolFont)
                        .foregroundStyle(.white)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(FrostPress(shape: Circle()))
                // The one solid button, as Firn's buttons are ink: the
                // space's vivid color under the frost's rim and hairline.
                .background {
                    FirnFrost(shape: Circle(), fill: Theme.spaceVivid(space.color))
                }
                .accessibilityLabel("Done")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, AddressBar.sideInset)
        .padding(.top, 8)
        .padding(.bottom, 0)
        // A space changed elsewhere (the menu, the command bar) mid-slide.
        .onChange(of: space.id) { if !finishing { progress = 0 } }
        .onChange(of: touching) { _, now in
            guard !now, !finishing, progress != 0 else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) { progress = 0 }
        }
    }

    /// The name, and the dots under it once there's more than one space.
    private var label: some View {
        VStack(spacing: 4) {
            Text(space.name)
                .font(.headline)
                // The same ink as + : the glass is already tinted, so the
                // words carry no color of their own (David, 2026-11-04).
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if spaces.count > 1 {
                SpaceDots(spaces: spaces, current: space.id)
            }
        }
        .padding(.horizontal, 24)
    }

    private var pill: some View {
        label
            // The name and dots change at once, never cross-fading (the old
            // name came back for a frame as a slide landed).
            .transaction { $0.animation = nil }
            .opacity(wordsIn)
            // Sliding, the words fade and dissolve toward the seam with
            // their pill, as the address bar's do.
            .opacity(slide?.wordsOpacity ?? 1)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .mask {
                if let slide {
                    GeometryReader { geo in
                        let held = slide.pills(in: geo.size).held
                        slide.wordsMask(width: held.width)
                            .clipShape(Capsule())
                            .frame(width: held.width, height: held.height)
                            .position(x: held.midX, y: held.midY)
                    }
                } else {
                    Rectangle().padding(-400)
                }
            }
            .background {
                GeometryReader { geo in
                    let pills = (slide ?? BarSlide(progress: 0)).pills(in: geo.size)
                    BarFrost(shape: Capsule(), space: space.color)
                        .frame(width: pills.held.width, height: pills.held.height)
                        .opacity(pills.heldOpacity)
                        .position(x: pills.held.midX, y: pills.held.midY)
                    // The coming space's own pill, in its own tint, growing
                    // out from the other button.
                    if let coming = pills.coming, let next = neighbor(progress) {
                        BarFrost(shape: Capsule(), space: next.color)
                            .frame(width: coming.width, height: coming.height)
                            .opacity(pills.comingOpacity)
                            .position(x: coming.midX, y: coming.midY)
                    }
                }
            }
            .contentShape(Capsule())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pillFrame = $0 }
            .onTapGesture { if progress == 0 { openMenu(pillFrame) } }
            .gesture(spaceSwipe)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spaces.count > 1 ? "\(space.name), space \(index + 1) of \(spaces.count)" : space.name)
            .accessibilityHint("Shows your spaces.")
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityAction { openMenu(pillFrame) }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: if let next = neighbor(-1) { select(next) }
                case .decrement: if let next = neighbor(1) { select(next) }
                @unknown default: break
                }
            }
    }

    /// Sideways on the pill: the seam follows the finger across it.
    private var spaceSwipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { drag in
                guard !finishing, abs(drag.translation.width) > abs(drag.translation.height) || progress != 0
                else { return }
                let width = max(pillFrame.width, 1)
                let t = min(max(drag.translation.width / width, -1), 1)
                progress = neighbor(t) == nil ? 0 : t
            }
            .onEnded { drag in
                guard !finishing, progress != 0 else { return }
                let width = max(pillFrame.width, 1)
                let flung = drag.predictedEndTranslation.width / width
                let direction: CGFloat = progress > 0 ? 1 : -1
                guard let next = neighbor(direction),
                      abs(progress) > 0.4 || (flung * direction > 0.8) else {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) { progress = 0 }
                    return
                }
                finishing = true
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.25)) {
                    progress = direction
                } completion: {
                    // The coming pill is whole: it becomes the space's own,
                    // in the same spot, with nothing to see as it swaps.
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) {
                        progress = 0
                        wordsIn = 0
                    }
                    finishing = false
                    select(next)
                    withAnimation(.easeOut(duration: 0.18)) { wordsIn = 1 }
                }
            }
    }
}

/// One small dot per space under its name, the space on screen's in its
/// color, the rest faint, as on the Mac (`Firn/SpaceRow.swift`). Silent:
/// VoiceOver hears "space 2 of 3" on the pill instead.
private struct SpaceDots: View {
    let spaces: [Space]
    let current: UUID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink = Theme.spaceInk(spaces.first { $0.id == current }?.color ?? "glacier")
        HStack(spacing: 6) {
            ForEach(spaces) { space in
                Circle()
                    .fill(space.id == current ? ink : Theme.faint.opacity(0.6))
                    .frame(width: 5, height: 5)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: current)
        .accessibilityHidden(true)
    }
}
