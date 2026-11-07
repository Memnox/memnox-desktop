import SwiftUI

/// One choice a select offers: the value it sets and the words it shows.
struct SelectOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

/// The console's select, in place of the system's popup button: the chosen words in a bordered field at radius 6 with
/// the up and down chevrons at its end, lit under the pointer, opening a menu that ticks the one chosen.
struct ConsoleSelect<Value: Hashable>: View {
    /// What the select chooses, for VoiceOver and on hover.
    let label: String
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: SelectSymbol.tick)
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: Memnox.Spacing.small) {
                Text(chosen)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.small)
                Image(systemName: SelectSymbol.chevrons)
                    .font(.system(size: Memnox.TextSize.micro, weight: .semibold))
                    .foregroundStyle(Memnox.Console.muted)
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
            .foregroundStyle(Memnox.Console.foreground)
            .padding(.horizontal, Memnox.Spacing.large)
            .frame(height: Memnox.Console.controlHeight)
            .background(hovering ? Memnox.Console.hover : Memnox.Console.field, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.controlEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
            .animation(.easeOut(duration: Memnox.Motion.quick), value: hovering)
        }
        // A plain button menu draws the whole label, so the bordered field shows rather than a bare link.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
        .pointingHand()
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(chosen)
    }

    /// The chosen option's words, or the first option's while the selection names none of them.
    private var chosen: String {
        options.first { $0.value == selection }?.title ?? options.first?.title ?? ""
    }
}

/// The select's two symbols, outside the generic view since a generic type cannot hold stored statics.
private enum SelectSymbol {
    static let chevrons = "chevron.up.chevron.down"
    static let tick = "checkmark"
}
