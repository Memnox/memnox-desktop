import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The walk through: one page per file, turning on its own at the pace the voice says each note,
/// until the person turns a page themselves, after which the pages are theirs to turn.
struct WalkView: View {
    let walk: WalkCard
    let close: () -> Void
    let open: (() -> Void)?
    let hovering: (Bool) -> Void
    @StateObject private var entrance = CardEntrance()
    @State private var page = 0
    @State private var turning: Task<Void, Never>?
    /// Tall enough for a note and twelve changed lines, so turning a page never resizes the card.
    private static let pageHeight: CGFloat = 300
    /// The voice's pace, about fourteen characters a second.
    private static let charactersPerSecond: Double = 14
    /// Even a short note stays up long enough to be read.
    private static let shortestPage: Double = 4
    private static let nanosecondsPerSecond: Double = 1_000_000_000

    private enum Layout {
        static let noteLineSpacing: CGFloat = 3
        /// A page button with nowhere to turn stays in place but dims.
        static let unavailableOpacity = 0.35
        static let turnResponse = 0.45
        static let turnDamping = 0.86
    }

    private enum Symbol {
        static let back = "chevron.left"
        static let next = "chevron.right"
        static let open = "arrow.up.forward.app"
    }

    /// Roughly how long the voice takes to say a page's note.
    static func seconds(for page: WalkPage) -> Double {
        max(shortestPage, Double(page.note.count) / charactersPerSecond)
    }

    var body: some View {
        let current = walk.pages[min(page, walk.pages.count - 1)]
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            CardHeader(title: walk.title, subtitle: walk.host?.app, close: close) {
                LogoMark(size: FloatingCard.markSize)
            } accessory: {
                Text("\(page + 1) of \(walk.pages.count)")
                    .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                    .foregroundStyle(Memnox.Palette.muted)
                    .contentTransition(.numericText(value: Double(page)))
            }
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                FileList(files: [CardFile(path: current.path, added: current.added, removed: current.removed)], counting: entrance.shown)
                Text(current.note)
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.foreground.opacity(Memnox.Ink.primary))
                    .lineSpacing(Layout.noteLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                if !current.lines.isEmpty {
                    CodeExcerpt(excerpt: CardExcerpt(path: current.path, lines: current.lines))
                }
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .frame(height: Self.pageHeight, alignment: .top)
            .clipped()
            HStack(spacing: Memnox.Spacing.medium) {
                PageDots(count: walk.pages.count, current: page)
                Spacer()
                CardButton(title: "Back", icon: Symbol.back, primary: false) { turn(to: page - 1) }
                    .opacity(page == 0 ? Layout.unavailableOpacity : 1)
                    .disabled(page == 0)
                CardButton(title: "Next", icon: Symbol.next, primary: false) { turn(to: page + 1) }
                    .opacity(page == walk.pages.count - 1 ? Layout.unavailableOpacity : 1)
                    .disabled(page == walk.pages.count - 1)
                if let open { CardButton(title: "Open", icon: Symbol.open, primary: true, action: open) }
            }
        }
        .modifier(CardFace(entrance: entrance, hovering: hovering))
        .onAppear { turnOnItsOwn() }
        .onDisappear { turning?.cancel() }
    }

    /// The person turned it, so it stops turning on its own and stays where they put it.
    private func turn(to target: Int) {
        turning?.cancel()
        move(to: target)
    }

    private func move(to target: Int) {
        guard walk.pages.indices.contains(target) else { return }
        withAnimation(.spring(response: Layout.turnResponse, dampingFraction: Layout.turnDamping)) { page = target }
    }

    private func turnOnItsOwn() {
        let pages = walk.pages
        turning = Task { @MainActor in
            for index in pages.indices.dropLast() {
                try? await Task.sleep(nanoseconds: UInt64(Self.seconds(for: pages[index]) * Self.nanosecondsPerSecond))
                guard !Task.isCancelled else { return }
                move(to: index + 1)
            }
        }
    }
}

/// A dot per page, the current one long and lit, so where the walk is reads at a glance.
struct PageDots: View {
    let count: Int
    let current: Int

    private enum Layout {
        static let spacing: CGFloat = 5
        static let size: CGFloat = 6
        /// The current page's dot is drawn long, so it reads apart from the rest.
        static let currentLength: CGFloat = 16
        static let restingOpacity = 0.22
        static let springResponse = 0.4
        static let springDamping = 0.8
    }

    var body: some View {
        HStack(spacing: Layout.spacing) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Memnox.Palette.primary : Color.white.opacity(Layout.restingOpacity))
                    .frame(width: index == current ? Layout.currentLength : Layout.size, height: Layout.size)
            }
        }
        .animation(.spring(response: Layout.springResponse, dampingFraction: Layout.springDamping), value: current)
    }
}
