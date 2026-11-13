import SwiftUI

/// Three small dots that brighten one after another, like someone typing
/// in Messages: shown where a new group's name will be while the on-device
/// model names it (David, 2026-11-07). Slow and soft, in the name's own
/// color. With Reduce Motion they hold still, half lit.
///
/// It only runs for the few seconds a group is being named, so nothing
/// animates while Firn is idle.
struct NamingDots: View {
    /// The name's color; the dots take it at partial strength.
    let color: Color
    var size: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        HStack(spacing: size) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .opacity(reduceMotion ? 0.5 : (lit ? 0.85 : 0.25))
                    .animation(
                        reduceMotion ? nil
                            : .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.2),
                        value: lit
                    )
            }
        }
        .onAppear { lit = true }
        .accessibilityHidden(true)
    }
}

/// What VoiceOver needs to hear a group's name as it arrives: its first
/// name (the dots giving way), or a new one that followed its tabs. A
/// rename by hand isn't announced: the person just typed it.
struct GroupNameState: Equatable {
    let naming: Bool
    let name: String

    func arrived(_ now: GroupNameState, namedByHand: Bool) -> Bool {
        if naming { return !now.naming }
        return !now.naming && name != now.name && !namedByHand
    }
}
