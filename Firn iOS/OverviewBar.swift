import FirnCore
import SwiftUI

/// The overview's bar, balanced like Safari's: + on the left, the space's
/// name in a frosted pill in the middle (the switcher and its dots come
/// with phase 4), and a round check on the right in a vivid version of the
/// space's color. All on Firn's frost (`BarFrost`), over the list's soft
/// edge blur; pressed, the warm wash.
struct OverviewBar: View {
    let space: Space
    let newTab: () -> Void
    let done: () -> Void

    /// Back's and the tabs button's size, so + and the check sit exactly
    /// where they were.
    private static let height = BarButton.glassSize

    var body: some View {
        ZStack {
            Text(space.name)
                .font(.headline)
                // The same ink as + : the glass is already tinted, so the
                // words carry no color of their own (David, 2026-11-04).
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .frame(height: Self.height)
                .background { BarFrost(shape: Capsule(), space: space.color) }
                .padding(.horizontal, Self.height + 16)
                .accessibilityAddTraits(.isHeader)
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
    }
}
