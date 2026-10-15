import SwiftUI

/// Light, Dark or System, chosen by picture, with a line saying the notch stays dark whichever is picked.
struct AppearancePage: View {
    @AppStorage(Appearance.key) private var chosen = Appearance.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            AppearancePicker(chosen: Binding(get: { chosen }, set: { look in
                chosen = look
                Appearance.choose(Appearance(rawValue: look) ?? .system)
            }))
            .surface()
            // Said here, since a person who picks Light would otherwise wonder why the notch did not follow.
            Text("The notch stays dark in every look, because it grows out of the black notch at the top of the screen.")
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Memnox.Spacing.xSmall)
        }
    }
}

/// Light, Dark or System as three small pictures of a screen, the chosen one ringed in the accent, so the person picks a
/// look by seeing it rather than reading it, as the iPhone app does.
struct AppearancePicker: View {
    @Binding var chosen: String

    private enum Layout {
        static let height: CGFloat = 92
        static let width: CGFloat = 136
        static let radius: CGFloat = 12
        static let innerRadius: CGFloat = 8
        static let inset: CGFloat = 10
        static let lineHeight: CGFloat = 3
        static let longLine: CGFloat = 0.55
        static let shortLine: CGFloat = 0.35
        static let dot: CGFloat = 12
        static let ring: CGFloat = 2
    }

    /// The miniature's own colours, fixed so each picture shows its look whatever the window is in.
    private enum Mini {
        static let lightPage = Color(hex: 0xFFFFFF)
        static let lightCard = Color(hex: 0xF4F4F6)
        static let lightLine = Color(hex: 0x8E8E93)
        static let darkPage = Color(hex: 0x0B0B0C)
        static let darkCard = Color(hex: 0x1C1C1E)
        static let darkLine = Color(hex: 0x636366)
    }

    var body: some View {
        HStack(spacing: Memnox.Spacing.xLarge) {
            ForEach(Appearance.picked, id: \.self) { look in option(look) }
            Spacer(minLength: 0)
        }
        .padding(Memnox.Spacing.xLarge)
    }

    private func option(_ look: Appearance) -> some View {
        let picked = look.rawValue == chosen
        return Button {
            withAnimation(.easeOut(duration: Memnox.Motion.quick)) { chosen = look.rawValue }
        } label: {
            VStack(spacing: Memnox.Spacing.medium) {
                thumbnail(look)
                    .frame(width: Layout.width, height: Layout.height)
                    .overlay(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
                        .strokeBorder(picked ? Memnox.Palette.primary : Memnox.ink(Memnox.Ink.edge),
                                      lineWidth: picked ? Layout.ring : Memnox.Stroke.hairline))
                Text(look.title)
                    .font(Memnox.sans(Memnox.TextSize.body, picked ? .semibold : .regular))
                    .foregroundStyle(picked ? Memnox.Palette.primary : Memnox.ink(Memnox.Ink.primary))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(look.title))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// A screen in miniature: a card with two lines of text and the orb's dot, light, dark, or split for System.
    private func thumbnail(_ look: Appearance) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
        return ZStack {
            switch look {
            case .light: miniature(page: Mini.lightPage, card: Mini.lightCard, line: Mini.lightLine)
            case .dark: miniature(page: Mini.darkPage, card: Mini.darkCard, line: Mini.darkLine)
            case .system:
                miniature(page: Mini.darkPage, card: Mini.darkCard, line: Mini.darkLine)
                miniature(page: Mini.lightPage, card: Mini.lightCard, line: Mini.lightLine)
                    .mask(Diagonal())
            }
        }
        .clipShape(shape)
    }

    private func miniature(page: Color, card: Color, line: Color) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 2 * Layout.inset
            ZStack(alignment: .topLeading) {
                page
                RoundedRectangle(cornerRadius: Layout.innerRadius, style: .continuous)
                    .fill(card)
                    .padding(Layout.inset)
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    Capsule().fill(line).frame(width: width * Layout.longLine, height: Layout.lineHeight)
                    Capsule().fill(line).frame(width: width * Layout.shortLine, height: Layout.lineHeight)
                }
                .padding(Layout.inset * 2)
                Circle()
                    .fill(Memnox.Palette.primary)
                    .frame(width: Layout.dot, height: Layout.dot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(Layout.inset * 2)
            }
        }
    }

    /// The upper left half of a rectangle, cut corner to corner, the light half of the System picture.
    private struct Diagonal: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
