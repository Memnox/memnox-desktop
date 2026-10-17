import AppKit
import MemnoxVoiceCore
import SwiftUI

/// How each tool looks: its colour, its mark, and what its own send button says.
enum ToolBrand {
    private struct Look {
        let color: UInt32
        let file: String
        let send: String
    }

    private static let looks: [String: Look] = [
        "slack": Look(color: 0x4A154B, file: "slack", send: "Send"),
        "github": Look(color: 0x238636, file: "github", send: "Comment"),
        "linear": Look(color: 0x5E6AD2, file: "linear", send: "Comment"),
        "gmail": Look(color: 0xEA4335, file: "gmail", send: "Send"),
        "googledocs": Look(color: 0x4285F4, file: "googledocs", send: "Save"),
        "notion": Look(color: 0x2F3437, file: "notion", send: "Save"),
    ]

    /// A tool with no look of its own is drawn in the Memnox blue, so it is never mistaken for one that has.
    private static let fallback = Look(color: 0x1E86EE, file: "", send: "Send")
    /// The bundle's folder of tool marks, copied in by the build script.
    private static let folder = "ToolLogos"
    private static let fileExtension = "svg"
    private static var cache: [String: NSImage] = [:]

    static func color(_ toolkit: String) -> Color { Color(hex: look(toolkit).color) }
    static func sendLabel(_ toolkit: String) -> String { look(toolkit).send }

    /// The tool's mark as a template, so it is drawn in whatever colour sits on its tile.
    @MainActor
    static func mark(_ toolkit: String) -> NSImage? {
        let file = look(toolkit).file
        guard !file.isEmpty else { return nil }
        if let kept = cache[file] { return kept }
        guard let url = Bundle.main.url(forResource: file, withExtension: fileExtension, subdirectory: folder),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        cache[file] = image
        return image
    }

    private static func look(_ toolkit: String) -> Look { looks[toolkit] ?? fallback }
}

/// Each tool's logo as Composio draws it in its own catalogue, fetched once and kept for the session.
@MainActor
enum ComposioLogos {
    /// Composio's logo address for a toolkit slug, the one its catalogue hands back as the toolkit's logo.
    private static let base = "https://logos.composio.dev/api/"
    private static var kept: [String: NSImage] = [:]
    /// A slug that failed once is not asked for again, so a missing logo never costs a request per redraw.
    private static var missing: Set<String> = []

    static func cached(_ toolkit: String) -> NSImage? { kept[toolkit] }

    static func load(_ toolkit: String) async -> NSImage? {
        if let image = kept[toolkit] { return image }
        guard !missing.contains(toolkit), let url = URL(string: base + toolkit) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data)
        else {
            missing.insert(toolkit)
            return nil
        }
        kept[toolkit] = image
        return image
    }
}

/// A tool's Composio logo in its own colours on a light tile, as an app icon sits; until it arrives, or
/// where Composio has none, the bundled mark on the tool's colour, or its first letter.
struct ToolMark: View {
    let toolkit: String
    let side: CGFloat
    @State private var logo: NSImage?

    private static let markShare: CGFloat = 0.58
    private static let logoShare: CGFloat = 0.72
    private static let cornerShare: CGFloat = 0.26

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: side * Self.cornerShare, style: .continuous)
        ZStack {
            if let logo = logo ?? ComposioLogos.cached(toolkit) {
                tile.fill(Color.white)
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side * Self.logoShare, height: side * Self.logoShare)
            } else {
                tile.fill(ToolBrand.color(toolkit))
                fallback
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .task(id: toolkit) { logo = await ComposioLogos.load(toolkit) }
    }

    @ViewBuilder private var fallback: some View {
        if let image = ToolBrand.mark(toolkit) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side * Self.markShare, height: side * Self.markShare)
                .foregroundStyle(Color.white)
        } else {
            Text(String(ToolkitName.of(toolkit).prefix(1)))
                .font(Memnox.sans(side * Self.markShare, .bold))
                .foregroundStyle(Color.white)
        }
    }
}

/// Under the notch: the tools the person asked for and has not signed in to, one tap each to sign in once.
struct IslandSignInRow: View {
    @ObservedObject var model: IslandModel

    private enum Layout {
        static let markSide: CGFloat = 22
        /// The pointer target around each mark, larger than the mark so it is easy to hit.
        static let hitSide: CGFloat = 30
        static let againBadge: CGFloat = 11
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 3
    }

    private static let againSymbol = "arrow.triangle.2.circlepath"

    var body: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            Text(model.signIns.contains { $0.signsInAgain } ? "Sign in" : "Sign in to use")
                .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                .padding(.trailing, Memnox.Spacing.xSmall)
            ForEach(model.signIns) { tool in
                Button { model.openSignIn(tool) } label: { mark(tool) }
                    .buttonStyle(PressableStyle())
                    .help(label(tool))
                    .accessibilityLabel(label(tool))
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(Memnox.Ink.edge)))
    }

    private func mark(_ tool: ToolSignIn) -> some View {
        ToolMark(toolkit: tool.toolkit, side: Layout.markSide)
            .overlay(alignment: .bottomTrailing) {
                // Signed in as somebody else before: the badge says this one signs in again.
                if tool.signsInAgain {
                    Image(systemName: Self.againSymbol)
                        .font(.system(size: Layout.againBadge * 0.6, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: Layout.againBadge, height: Layout.againBadge)
                        .background(Circle().fill(IslandPalette.amber))
                        .offset(x: Layout.againBadge / 3, y: Layout.againBadge / 3)
                }
            }
            .frame(width: Layout.hitSide, height: Layout.hitSide)
            .contentShape(Rectangle())
    }

    private func label(_ tool: ToolSignIn) -> String {
        let name = ToolkitName.of(tool.toolkit)
        return tool.signsInAgain ? "Sign in to \(name) again, with your own account" : "Sign in to \(name)"
    }
}

/// Under the notch the moment a sign in finishes: the tool, whose account it reached, and a seal where the
/// workspace knows it is theirs. Where nothing ties it to them yet it offers Not me and asks nothing else,
/// since the first thing they send with Touch ID ties it to them.
struct IslandSignedInPill: View {
    @ObservedObject var model: IslandModel
    let card: SignedInCard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let markSide: CGFloat = 18
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 6
    }

    private enum Symbol {
        static let matched = "checkmark.seal.fill"
    }

    var body: some View {
        HStack(spacing: Memnox.Spacing.small) {
            ToolMark(toolkit: card.notice.toolkit, side: Layout.markSide)
            Text(card.who.map { "\(card.tool) · \($0)" } ?? "Signed in to \(card.tool)")
                .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            if card.unverified {
                Button("Not me") { model.notMine(card) }
                    .buttonStyle(IslandButton(primary: false))
                    .help("Sign in again with your own account")
            } else {
                Image(systemName: Symbol.matched)
                    .font(.system(size: Memnox.TextSize.caption))
                    .foregroundStyle(IslandPalette.green)
                    .accessibilityLabel("your account")
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(Memnox.Ink.edge)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.who.map { "Signed in to \(card.tool) as \($0)" } ?? "Signed in to \(card.tool)")
        .animation(reduceMotion ? nil : .snappy, value: card)
    }
}
