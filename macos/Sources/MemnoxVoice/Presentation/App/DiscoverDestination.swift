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

    func said(_ outcome: IndexSourceOutcome) {
        switch outcome {
        case .proposed(let line), .done(let line): note = line
        case .failed(let why): note = why
        }
    }

    /// Installs and says how it ended; nothing installed here is live until it is accepted or signed.
    func install(_ name: String, version: String?) {
        Task { said(await index.install(name, version: version)) }
    }

    /// Names another index, which waits on the island, or the marketplace when nil, which holds at once.
    func setSource(_ address: String?) async -> IndexSourceOutcome {
        let outcome = await index.setSource(address)
        said(outcome)
        return outcome
    }
}

private enum DiscoverLayout {
    static let cardWidth: CGFloat = 260
    static let searchWidth: CGFloat = 320
    /// The wide column takes this much more than the narrow one, as a skill's own page does.
    static let leftShare: CGFloat = 1.4
    /// Words go to the runtime this long after the last key, so each key is not a request.
    static let typingPause: UInt64 = 250_000_000
    static let addressWidth: CGFloat = 360
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
        ListingsSource(screen: screen, view: view)
    }
}

/// Where listings come from: another index is only proposed and signed on the island, the marketplace again is at once.
private struct ListingsSource: View {
    @ObservedObject var screen: IndexScreen
    let view: CommunityIndexView
    @State private var address = ""

    var body: some View {
        let usable = IndexLines.isIndexAddress(address)
        let busy = screen.index.busy == CommunityIndex.settingSource
        ShellSection(title: "Where listings come from") {
            if view.marketplace { StatusWord(.good, "Memnox marketplace") } else { StatusWord(.attention, "An index you named") }
        } content: {
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                Text(IndexLines.source(view))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Memnox.Spacing.regular) {
                    TextField("https://example.com/index.json", text: $address)
                        .kitField()
                        .frame(maxWidth: DiscoverLayout.addressWidth)
                        .onSubmit(propose)
                        .accessibilityLabel("Address of an index.json")
                    Button("Propose this index", systemImage: "globe", action: propose)
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(!usable || busy)
                }
                if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !usable {
                    StatusWord(.attention, IndexLines.addressWanted)
                }
                QuietLine("Another index decides what can be installed here, so naming one waits on the island for your signature with Touch ID.")
                Button("Use the Memnox marketplace") { Task { _ = await screen.setSource(nil) } }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(view.marketplace || busy)
            }
            .padding(ShellMetrics.rowPaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        }
    }

    private func propose() {
        guard IndexLines.isIndexAddress(address), screen.index.busy != CommunityIndex.settingSource else { return }
        let typed = address
        Task {
            if case .failed = await screen.setSource(typed) { return }
            address = ""
        }
    }
}

/// What a listing needs in one line, the paths, hosts, commands, servers and tools themselves on open.
private struct NeedsView: View {
    let needs: IndexNeedsView?
    @State private var open = false

    var body: some View {
        let groups = IndexLines.needsGroups(needs)
        if groups.isEmpty {
            summary
        } else {
            DisclosureGroup(isExpanded: $open) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.small) {
                                Text(group.title)
                                    .font(Memnox.Console.sans(Memnox.TextSize.footnote, .semibold))
                                    .foregroundStyle(Memnox.Console.foreground)
                                Text(group.caption)
                                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                                    .foregroundStyle(Memnox.Console.muted)
                            }
                            ForEach(group.items, id: \.self) { item in
                                Text(item)
                                    .font(Memnox.Console.sans(Memnox.TextSize.micro))
                                    .foregroundStyle(Memnox.Console.foreground)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, Memnox.Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                summary
            }
        }
    }

    private var summary: some View {
        Text(IndexLines.needsSummary(needs))
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What to know before installing, each sentence in amber beside its words, since colour alone says nothing.
private struct WarningsView: View {
    let warnings: [String]

    var body: some View {
        if let count = IndexLines.warningsCount(warnings) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                StatusWord(.attention, count)
                ForEach(warnings, id: \.self) { warning in
                    Text(warning)
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.warm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
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
                    .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                Text("\(IndexLines.kindWord(entry.kind)) · \(IndexLines.publisher(entry.publisher))")
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(1)
            }
            Text(entry.description)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.foreground)
                .lineLimit(2)
            HStack(spacing: Memnox.Spacing.large) {
                if entry.unsafe { StatusWord(.bad, "Marked unsafe") } else { Text(IndexLines.latest(entry)) }
                if let installed = IndexLines.installed(entry) { StatusWord(.good, installed) }
                Text(IndexLines.supportedAgents(entry.agents))
            }
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .lineLimit(1)
            Text(IndexLines.needsSummary(entry.needs))
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.muted)
                .lineLimit(1)
            if let warnings = IndexLines.warningsCount(entry.warnings) { StatusWord(.attention, warnings) }
            ShellDivider()
            Button("View listing", action: view).buttonStyle(KitButton(kind: .secondary))
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
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
                    .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Memnox.Spacing.medium)
                Text(IndexLines.kindWord(entry.kind))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
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
                .font(Memnox.Console.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
            FactList(facts: facts)
            ShellSection(title: "What it needs") {
                NeedsView(needs: entry.needs)
            }
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
                WarningsView(warnings: entry.warnings)
                QuietLine(IndexLines.needsSummary(entry.needs))
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
            .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            if let latest = entry.latest {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Memnox.Spacing.xLarge) {
                    GridRow {
                        Text("Digest").font(Memnox.Console.sans(Memnox.TextSize.footnote)).foregroundStyle(Memnox.Console.muted)
                        Text(latest.digest)
                            .font(Memnox.Console.code(Memnox.TextSize.micro))
                            .foregroundStyle(Memnox.Console.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
