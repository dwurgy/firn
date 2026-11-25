import FirnCore
import SwiftUI

// The welcome's pieces (docs/design/frost), on the Mac and the iPhone: the
// headline, the pill, the choice cards, and the steps both have.

extension View {
    /// SF at the drawing's size; it follows the person's text size (the
    /// Mac has none to follow).
    func frostFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(FrostFont(size: size, weight: weight))
    }
}

private struct FrostFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

/// A Frost headline: Gooper Deck, its second half in SemiBold (emphasis is
/// weight, never color).
struct FrostTitle: View {
    private let plain: String
    private let strong: String
    @ScaledMetric private var size: CGFloat
    @Environment(\.dynamicTypeSize) private var textSize

    init(_ plain: String, _ strong: String, size: CGFloat) {
        self.plain = plain
        self.strong = strong
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    private var words: AttributedString {
        var start = AttributedString(plain + " ")
        start.font = BrandFont.gooper(size)
        // A few words, kept on one line unless the text is very large.
        var end = AttributedString(textSize.isAccessibilitySize ? strong : strong.replacing(" ", with: "\u{00A0}"))
        end.font = BrandFont.gooper(size, emphasis: true)
        return start + end
    }

    var body: some View {
        Text(words)
            .foregroundStyle(Theme.Frost.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The one glass pill on each of the welcome's screens: "Frosty, no tint"
/// (native glass over the thinnest blur) on macOS 26, a frosted material
/// before, solid with Reduce Transparency.
struct FrostPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FrostPill(configuration: configuration)
    }
}

private struct FrostPill: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Native glass casts its own.
    private var shadow: Color {
        if #available(macOS 26, *) { .clear } else { Theme.Frost.shadow }
    }

    var body: some View {
        let shape = Capsule()
        configuration.label
            .frostFont(16)
            .lineLimit(1)
            .foregroundStyle(Theme.Frost.ink)
            .padding(.horizontal, 28)
            .frame(height: 50)
            .background {
                FrostSurface(shape: shape, hovering: hovering, pressed: configuration.isPressed)
                    .shadow(color: shadow, radius: 14, y: 8)
            }
            .overlay {
                if isFocused { shape.strokeBorder(Theme.Frost.ink, lineWidth: 2).padding(-5) }
            }
            .contentShape(shape)
            .fixedSize()
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }

}

/// The welcome's glass: "Frosty, no tint" (native glass over the thinnest
/// blur) on macOS 26, a frosted material before, solid with Reduce
/// Transparency.
struct FrostSurface<S: InsettableShape>: View {
    let shape: S
    var hovering = false
    var pressed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(Theme.Frost.glassSolid)
                    .overlay { shape.strokeBorder(Theme.Frost.fieldLine, lineWidth: 1) }
            } else if #available(macOS 26, *) {
                shape.fill(.clear)
                    .glassEffect(.regular, in: shape)
                    .background { shape.fill(.ultraThinMaterial) }
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(Theme.Frost.glass) }
                    .overlay { shape.strokeBorder(Theme.Frost.rimLine, lineWidth: 1) }
            }
        }
        .overlay { shape.fill(pressed ? Theme.press : hovering ? Theme.hover : .clear) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One choice on a step: a glass card, outlined in ink with a check when chosen.
struct FrostChoice: View {
    let title: String
    let caption: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .frostFont(16, weight: .semibold)
                    Text(caption)
                        .frostFont(14)
                        .foregroundStyle(Theme.Frost.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Frost.skyLow)
                    .frame(width: 22, height: 22)
                    .background { Circle().fill(Theme.Frost.ink) }
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(Theme.Frost.ink)
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .padding(.vertical, 13)
            .background { FrostSurface(shape: shape, hovering: hovering) }
            .overlay { shape.strokeBorder(Theme.Frost.ink.opacity(isSelected ? 1 : 0), lineWidth: 1.5) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Every button that isn't the pill: plain words.
struct FrostPlainStyle: ButtonStyle {
    var quiet = false
    var underlined = false

    func makeBody(configuration: Configuration) -> some View {
        FrostPlainLabel(configuration: configuration, quiet: quiet, underlined: underlined)
    }
}

private struct FrostPlainLabel: View {
    let configuration: ButtonStyleConfiguration
    let quiet: Bool
    let underlined: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .frostFont(16)
            .underline(underlined)
            .foregroundStyle(quiet && !hovering ? Theme.Frost.muted : Theme.Frost.ink)
            .opacity(!isEnabled ? 0.5 : configuration.isPressed ? 0.6 : 1)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }
}

/// Where the step is: a dot for each, ink for this one.
struct StepDots: View {
    let count: Int
    let current: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Theme.Frost.ink : Theme.Frost.dot)
                    .frame(width: 7, height: 7)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// A new step's words fade up into place (6pt), once, as they appear.
/// Reduce Motion: they're simply there.
struct StepEntrance: ViewModifier {
    let duration: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: duration)) { shown = true }
            }
    }
}

/// Which search, and whether to show suggestions (the one place typing
/// goes over the network, so nothing is sent until the answer is yes).
struct SearchStep: View {
    let accent: Color
    @AppStorage(SearchEngine.preferenceKey) private var engine = SearchEngine.default
    @AppStorage(SearchSuggestions.preferenceKey) private var suggestions = false

    /// The welcome's three; more are in Settings.
    private static let engines: [(SearchEngine, String)] = [
        (.google, "The search most people know."),
        (.duckDuckGo, "Doesn’t keep track of your searches."),
        (.bing, "Microsoft’s search."),
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Self.engines, id: \.0) { choice, note in
                FrostChoice(title: choice.name, caption: note, isSelected: engine == choice) { engine = choice }
            }
        }
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show suggestions as you type")
                    .frostFont(16)
                Text("Your search engine sees what you type.")
                    .frostFont(14)
                    .foregroundStyle(Theme.Frost.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // VoiceOver reads these with the switch, once.
            .accessibilityHidden(true)
            Toggle("Show suggestions as you type", isOn: $suggestions)
                .toggleStyle(.switch)
                // The space's color, not the system blue.
                .tint(accent)
                .labelsHidden()
                .accessibilityHint("Your search engine sees what you type.")
        }
        .padding(.horizontal, 4)
        .padding(.top, 28)
    }
}

/// The first space: its name and color change as they're picked.
struct SpaceStep: View {
    let store: BrowserStore
    @Binding var name: String
    @FocusState private var nameFocused: Bool

    private var space: Space { store.activeSpace }

    #if os(iOS)
    /// Two even rows: an iPhone has no room for eight in one.
    private static let swatchColumns = Array(repeating: GridItem(.fixed(44), spacing: 20), count: 4)
    #else
    private static let swatchColumns = [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 8)]
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                title("Name")
                TextField(Space.defaultName, text: $name)
                    .textFieldStyle(.plain)
                    .frostFont(17)
                    .focused($nameFocused)
                    .accessibilityLabel("Space name")
                    .onChange(of: name) { if name.count > Space.nameLimit { name = String(name.prefix(Space.nameLimit)) } }
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .tint(Theme.accent)
                    #endif
                    .onSubmit { store.updateSpace(space, name: name, color: space.color) }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                        shape.fill(Theme.Frost.field)
                            .overlay {
                                shape.strokeBorder(nameFocused ? Theme.Frost.ink : Theme.Frost.fieldLine,
                                                   lineWidth: nameFocused ? 2 : 1)
                            }
                    }
            }
            VStack(alignment: .leading, spacing: 10) {
                title("Color")
                LazyVGrid(columns: Self.swatchColumns, alignment: .leading, spacing: 8) {
                    ForEach(Theme.spaceColorNames, id: \.self) { choice in
                        FrostSwatch(name: choice, isSelected: space.color == choice) {
                            store.updateSpace(space, name: space.name, color: choice)
                        }
                    }
                }
                Text(space.color.capitalized)
                    .frostFont(14)
                    // The swatch itself says it.
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
    }

    private func title(_ words: String) -> some View {
        Text(words)
            .frostFont(14)
            .foregroundStyle(Theme.Frost.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A space's color: a disc, ringed in ink when chosen.
private struct FrostSwatch: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Theme.spaceColor(name))
                .frame(width: 38, height: 38)
                .frame(width: 44, height: 44)
                .overlay {
                    Circle().strokeBorder(Theme.Frost.ink.opacity(isSelected ? 1 : hovering ? 0.25 : 0), lineWidth: 1.5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isSelected)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: hovering)
        .help(name.capitalized)
        .accessibilityLabel(name.capitalized)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One suggested site: a tile of glass with its icon (its letter
/// until the icon arrives, or if it has none), ringed and checked in the
/// space's color when picked, and its name below.
struct SiteChoice: View {
    let name: String
    let icon: Data?
    let accent: Color
    let isOn: Bool
    let canPick: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    FrostSurface(shape: shape, hovering: hovering)
                    if let icon {
                        SiteIconView(icon: icon, size: 30) { EmptyView() }
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .transition(.opacity)
                    } else {
                        Text(name.prefix(1))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.Frost.muted)
                            .transition(.opacity)
                    }
                }
                .frame(width: 64, height: 64)
                .overlay { shape.strokeBorder(accent.opacity(isOn ? 1 : 0), lineWidth: 2) }
                .overlay(alignment: .topTrailing) {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            // Never pure white, as on Basecamp's letter tiles.
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(width: 20, height: 20)
                            .background { Circle().fill(accent) }
                            .background { Circle().fill(Theme.Frost.skyLow).padding(-2) }
                            .offset(x: 7, y: -7)
                            .transition(.opacity)
                    }
                }
                Text(name)
                    .frostFont(13)
                    .foregroundStyle(Theme.Frost.muted)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn && !canPick)
        .opacity(!isOn && !canPick ? 0.5 : 1)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: icon != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isOn)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
