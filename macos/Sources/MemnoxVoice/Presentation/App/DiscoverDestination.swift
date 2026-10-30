import MemnoxVoiceCore
import SwiftUI

/// The community index for the views: redrawn whenever the core's index changes, with the line the last press ended in.
@MainActor
final class IndexScreen: ObservableObject {
    let index: CommunityIndex
    /// Bumped when the index changes, so every view reading it is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the page until the next one.
    @Published var note: String?

    init(index: CommunityIndex) {
        self.index = index
        index.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    func said(_ outcome: IndexOutcome) {
        switch outcome {
        case .done(let line): note = line
        case .failed(let why): note = why
        }
    }

    /// Installs and says how it ended; nothing installed here is live until it is accepted or signed.
    func install(_ name: String, version: String?) {
        Task { said(await index.install(name, version: version)) }
    }
}

private enum DiscoverLayout {
    static let cardWidth: CGFloat = 260
    static let searchWidth: CGFloat = 320
    /// The wide column takes this much more than the narrow one, as a skill's own page does.
    static let leftShare: CGFloat = 1.4
    /// Words go to the runtime this long after the last key, so each key is not a request.
    static let typingPause: UInt64 = 250_000_000
}

/// The community index under the Skills Hub. Install never makes anything live: the runtime checks the digest, a skill
/// then waits in My Skills for acceptance, and a pack's rules each wait for Touch ID on the island.
struct DiscoverDestination: View {
    @ObservedObject var screen: IndexScreen
    let width: WidthClass
    @State private var query = ""
    @State private var category: String?
    @State private var opened: String?

    var body: some View {
        page
            .task { await screen.index.refresh() }
            .task(id: query) {
                guard query != screen.index.filter.query else { return }
                try? await Task.sleep(nanoseconds: DiscoverLayout.typingPause)
                guard !Task.isCancelled else { return }
                var filter = screen.index.filter
                filter.query = query
                await screen.index.refresh(filter)
            }
    }

    @ViewBuilder private var page: some View {
        let index = screen.index
        if let view = index.index {
            ShellScroll(width: width) {
                NoteBanner(text: screen.note)
                if let picked = view.entries.first(where: { $0.id == opened }) {
                    ListingDetail(screen: screen, entry: picked, width: width) { opened = nil }
                } else {
                    listings(view)
                }
            }
        } else if index.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the community index") { Task { await index.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func listings(_ view: CommunityIndexView) -> some View {
        let categories = IndexLines.categories(view.entries)
        let shown = IndexLines.inCategory(view.entries, category)
        HStack(spacing: Memnox.Spacing.regular) {
            SearchField(prompt: "Search skills and rule packs", text: $query).frame(maxWidth: DiscoverLayout.searchWidth)
            Spacer(minLength: Memnox.Spacing.medium)
            Button { Task { await screen.index.refresh(fresh: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(screen.index.busy == CommunityIndex.refreshing)
                .help("Read the index again now")
        }
        ScrollView(.horizontal) {
            HStack(spacing: Memnox.Spacing.small) {
                ForEach(IndexKindFilter.allCases, id: \.self) { kind in
                    FilterChip(title: kind.title, chosen: screen.index.filter.kind == kind) {
                        var filter = screen.index.filter
                        filter.kind = kind
                        Task { await screen.index.refresh(filter) }
                    }
                }
                if !categories.isEmpty {
                    ShellDivider().frame(width: Memnox.Stroke.hairline, height: Memnox.Spacing.xLarge)
                    FilterChip(title: "Every category", chosen: category == nil) { category = nil }
                }
                ForEach(categories, id: \.self) { each in
                    FilterChip(title: each, chosen: category == each) { category = each }
                }
            }
        }
        .scrollIndicators(.never)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show listings that are")
        QuietLine(IndexLines.state(view, now: Date()))
        if shown.isEmpty {
            EmptyState(symbol: "storefront", title: "Nothing in the index matches",
                       detail: "Try fewer words, another kind or every category, or read the index again with Refresh.")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DiscoverLayout.cardWidth), spacing: Memnox.Spacing.large)],
                      spacing: Memnox.Spacing.large) {
                ForEach(shown) { entry in
                    ListingCard(entry: entry) { opened = entry.id }
                }
            }
        }
        QuietLine("\(IndexLines.installWaits(kind: IndexKind.skill.rawValue, keyTitle: "Touch ID")) \(IndexLines.installWaits(kind: IndexKind.rulePack.rawValue, keyTitle: "Touch ID"))")
    }
}

private struct ListingCard: View {
    let entry: IndexEntryView
    let view: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(entry.name)
                    .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                Text("\(IndexLines.kindWord(entry.kind)) · \(IndexLines.publisher(entry.publisher))")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.muted)
                    .lineLimit(1)
            }
            Text(entry.description)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Palette.foreground)
                .lineLimit(2)
            HStack(spacing: Memnox.Spacing.large) {
                if entry.unsafe { StatusWord(.bad, "Marked unsafe") } else { Text(IndexLines.latest(entry)) }
                if let installed = IndexLines.installed(entry) { StatusWord(.good, installed) }
                Text(IndexLines.supportedAgents(entry.agents))
            }
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Palette.muted)
            .lineLimit(1)
            ShellDivider()
            Button("View listing", action: view).buttonStyle(KitButton(kind: .secondary))
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Memnox.Palette.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.name)
    }
}

/// One listing on the whole page, with its digest and every version, the unsafe ones marked and never offered.
private struct ListingDetail: View {
    @ObservedObject var screen: IndexScreen
    let entry: IndexEntryView
    let width: WidthClass
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) {
            HStack(spacing: Memnox.Spacing.regular) {
                Button("Discover", systemImage: "arrow.left", action: back).buttonStyle(KitButton(kind: .secondary))
                Text(entry.name)
                    .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Memnox.Spacing.medium)
                Text(IndexLines.kindWord(entry.kind))
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.muted)
            }
            if width == .wide || width == .medium {
                SharedColumns(leftShare: DiscoverLayout.leftShare, gap: ShellMetrics.sectionSpacing) {
                    what
                    install
                }
            } else {
                VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) {
                    what
                    install
                }
            }
        }
    }

    private var what: some View {
        var facts: [(String, String)] = [
            ("Publisher", entry.publisher.name),
            ("Category", entry.category ?? "None given"),
            ("License", entry.license ?? "None given"),
            ("Agents", IndexLines.supportedAgents(entry.agents)),
        ]
        if let installed = IndexLines.installed(entry) { facts.append(("Here", installed)) }
        return VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) {
            Text(entry.description)
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
            FactList(facts: facts)
            ShellSection(title: "Versions") {
                ShellPanel {
                    if let latest = entry.latest {
                        ShellRow(title: "v\(latest.version)", caption: "The newest version not marked unsafe") {
                            EmptyView()
                        } trailing: {
                            StatusWord(.good, "Latest")
                        }
                    }
                    ForEach(Array(entry.yanked.enumerated()), id: \.offset) { index, version in
                        if index > 0 || entry.latest != nil { ShellDivider() }
                        ShellRow(title: "v\(version)", caption: "Marked unsafe since it was published, so it is never installed") {
                            EmptyView()
                        } trailing: {
                            StatusWord(.bad, "Unsafe")
                        }
                    }
                }
                if let yanked = IndexLines.yanked(entry.yanked) { QuietLine(yanked) }
            }
        }
    }

    private var install: some View {
        let busy = screen.index.busy == entry.name
        return VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                if IndexLines.canInstall(entry) {
                    Button(busy ? "Installing" : "Install \(IndexLines.latest(entry))", systemImage: "arrow.down.circle") {
                        screen.install(entry.name, version: entry.latest?.version)
                    }
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy)
                } else {
                    StatusWord(.bad, "Every version is marked unsafe, so there is nothing to install")
                }
                QuietLine(IndexLines.installWaits(kind: entry.kind, keyTitle: "Touch ID"))
                QuietLine("The runtime checks what it downloads against the digest below before it writes anything.")
            }
            .padding(ShellMetrics.rowPaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Palette.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                .strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
            if let latest = entry.latest {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Memnox.Spacing.xLarge) {
                    GridRow {
                        Text("Digest").font(Memnox.sans(Memnox.TextSize.footnote)).foregroundStyle(Memnox.Palette.muted)
                        Text(latest.digest)
                            .font(Memnox.mono(Memnox.TextSize.micro))
                            .foregroundStyle(Memnox.Palette.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
