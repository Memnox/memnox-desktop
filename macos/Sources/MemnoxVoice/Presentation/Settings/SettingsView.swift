import AppKit
import SwiftUI

/// The one Memnox window, laid out as Vorssaint lays out its own: a sidebar panel inset on the window with a search
/// field and the pages in groups that fold, then Back and Forward in a capsule beside the page's name, and the page as
/// one column of cards.
struct SettingsView: View {
    @ObservedObject var models: SettingsModels
    @ObservedObject var navigation: SettingsNavigation
    /// Closes the window, for Escape.
    let close: () -> Void
    @State private var query = ""
    @State private var collapsed: Set<String> = []

    private enum Layout {
        static let sidebarWidth: CGFloat = 235
        /// A little more room on the sidebar's glass, where Vorssaint's inset panel used to leave a margin.
        static let sidebarInset: CGFloat = 8
        /// The window's buttons sit over the panel's top, so the search starts below them.
        static let trafficLightsRoom: CGFloat = 44
        /// Inside the panel, between its edge and the search field and the rows.
        static let sidebarPadding: CGFloat = 9
        static let rowHeight: CGFloat = 30
        static let rowPadding: CGFloat = 10
        static let rowRadius: CGFloat = 8
        static let rowIconWidth: CGFloat = 18
        static let rowIconSpacing: CGFloat = 9
        static let rowIconSize: CGFloat = 14
        static let rowTextSize: CGFloat = 13
        static let sectionTextSize: CGFloat = 12
        static let sectionTop: CGFloat = 14
        static let sectionBottom: CGFloat = 4
        static let chevronSize: CGFloat = 9
        static let chevronWidth: CGFloat = 12
        static let headerSpacing: CGFloat = 6
        /// The header row inside the page's panel, so with the panel's inset its capsule sits level with the window's buttons.
        static let headerHeight: CGFloat = 44
        static let headerLeading: CGFloat = 19
        static let headerSpacingToTitle: CGFloat = 13
        static let headerTitleSize: CGFloat = 15
    }

    private enum Symbol {
        static let open = "chevron.down"
        static let shut = "chevron.right"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Layout.sidebarWidth + Layout.sidebarInset)
                .background(WindowGlass(material: .sidebar))
            VStack(spacing: 0) {
                header
                SettingsColumn(
                    title: navigation.page == .overview ? nil : navigation.page.title,
                    subtitle: navigation.page == .overview ? nil : navigation.page.subtitle
                ) { page }
                    .environment(\.rimlessCards, true)
                    // Any button a page leaves unstyled is Vorssaint's grey capsule, so no system button shows here.
                    .buttonStyle(QuietButton())
                    .id(navigation.page)
            }
            .modifier(PagePanel())
            .padding([.top, .trailing, .bottom], Layout.sidebarInset)
        }
        // Edge to edge, so the sidebar's inset is measured from the window rather than from under its title bar.
        .ignoresSafeArea()
        // Only the sidebar is glass; the page is solid, as Vorssaint's is.
        .background(WindowGlass(material: .sidebar).ignoresSafeArea())
        .tint(Memnox.Palette.primary)
        .background(escapeKey)
        .task(id: models.setup.map(ObjectIdentifier.init)) { await models.setup?.check() }
    }

    private var header: some View {
        HStack(spacing: Layout.headerSpacingToTitle) {
            NavigationCapsule(
                canGoBack: navigation.canGoBack, canGoForward: navigation.canGoForward,
                back: navigation.goBack, forward: navigation.goForward
            )
            Text(navigation.page.title)
                .font(.system(size: Layout.headerTitleSize, weight: .semibold))
                .foregroundStyle(Memnox.Palette.foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, Layout.headerLeading)
        .frame(height: Layout.headerHeight)
        .background(Color.clear.contentShape(Rectangle()))
        .background(keys)
    }

    /// Command [ and Command ] go back and forward, as in Vorssaint and in a browser.
    private var keys: some View {
        ZStack {
            Button("Back", action: navigation.goBack).keyboardShortcut("[", modifiers: .command)
            Button("Forward", action: navigation.goForward).keyboardShortcut("]", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchField(prompt: "Search settings", text: $query)
                .padding(.horizontal, Layout.sidebarPadding)
                .padding(.top, Layout.trafficLightsRoom)
                .padding(.bottom, Layout.sidebarPadding)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if searching {
                        ForEach(matches) { page in sidebarRow(page) }
                    } else {
                        ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { _, group in
                            if let title = group.title {
                                sectionHeader(title)
                                if !collapsed.contains(title) { ForEach(group.pages) { page in sidebarRow(page) } }
                            } else {
                                ForEach(group.pages) { page in sidebarRow(page) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Layout.sidebarPadding)
                .padding(.bottom, Layout.sidebarPadding)
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sidebarRow(_ page: SettingsPage) -> some View {
        let chosen = navigation.page == page
        return Button { navigation.go(page) } label: {
            HStack(spacing: Layout.rowIconSpacing) {
                Image(systemName: page.symbol)
                    .font(.system(size: Layout.rowIconSize))
                    .foregroundStyle(chosen ? Color.white : Memnox.Palette.primary)
                    .frame(width: Layout.rowIconWidth)
                Text(page.title)
                    .font(.system(size: Layout.rowTextSize, weight: chosen ? .medium : .regular))
                    .foregroundStyle(chosen ? Color.white : Memnox.Palette.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.rowPadding)
            .frame(height: Layout.rowHeight)
            .background(chosen ? Memnox.Palette.primary : Color.clear,
                        in: RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous))
            // Under the blue of the chosen row, so only the others light.
            .hoverLight(radius: Layout.rowRadius, inset: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(page.subtitle)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// A group's name with a chevron that folds it away, as Vorssaint's sidebar groups fold.
    private func sectionHeader(_ title: String) -> some View {
        Button {
            withAnimation(.snappy) { if !collapsed.insert(title).inserted { collapsed.remove(title) } }
        } label: {
            HStack(spacing: Layout.headerSpacing) {
                Image(systemName: collapsed.contains(title) ? Symbol.shut : Symbol.open)
                    .font(.system(size: Layout.chevronSize, weight: .semibold))
                    .frame(width: Layout.chevronWidth)
                Text(title).font(.system(size: Layout.sectionTextSize, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Memnox.Palette.faint)
            .padding(.horizontal, Layout.headerSpacing)
            .padding(.top, Layout.sectionTop)
            .padding(.bottom, Layout.sectionBottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(collapsed.contains(title) ? "Show \(title)" : "Hide \(title)")
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Pages whose name or line says what was typed, in the sidebar's own order.
    private var matches: [SettingsPage] {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsPage.groups.flatMap(\.pages).filter {
            $0.title.localizedCaseInsensitiveContains(typed) || $0.subtitle.localizedCaseInsensitiveContains(typed)
        }
    }

    @ViewBuilder private var page: some View {
        if let menu = models.menu, let setup = models.setup {
            switch navigation.page {
            case .overview: OverviewPage(menu: menu, setup: setup, account: models.account, home: models.home, dictations: models.dictations, go: navigation.go)
            case .account:
                if let account = models.account { AccountPage(account: account, setup: setup) }
            case .permissions: SetupPermissionsCard(model: setup)
            case .connection: SetupMacCard(model: setup)
            case .phones: PhonesPage(menu: menu, setup: setup)
            case .tools: ToolsPage(tools: menu.tools)
            case .apps: YourAppsPage(tools: menu.tools)
            case .appearance: AppearancePage()
            case .voice: VoicePage(menu: menu, setup: setup)
            case .listening: ListeningPage(menu: menu, setup: setup)
            case .dictation:
                if let dictations = models.dictations { DictationPage(store: dictations) }
            case .help: HelpPage(menu: menu)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    /// Escape closes the window the way a sheet closes, through a button no one sees.
    private var escapeKey: some View {
        Button("Close", action: close)
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

/// The phones: pairing one, then the ones already paired with what each may do.
private struct PhonesPage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            SetupPhoneCard(model: setup)
            if !menu.devices.isEmpty {
                SettingsCard(title: "Paired phones") {
                    ForEach(menu.devices) { device in
                        if device.id != menu.devices.first?.id { Divider() }
                        DeviceRow(device: device, revoke: { menu.revoke(device) }, letDrive: { on in menu.letDrive(device, on) })
                    }
                }
            }
            if setup.serverPairing != nil { SetupServerCard(model: setup) }
        }
    }
}

/// Who thinks for the voice and which voice speaks, the Mac's own or a Kokoro one, in one row.
private struct VoicePage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        SetupVoiceCard(model: setup, menu: menu)
    }
}

/// The switches for when Memnox listens and speaks up, with catching up after time away, in two cards as Vorssaint
/// groups its own: hearing the person, then speaking to them.
private struct ListeningPage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject private var mute = VoiceMute.shared
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            SettingsCard(title: "Hearing you") {
                SwitchRow(symbol: MenuSymbol.wake, title: "Wake when I say \u{201C}Memnox\u{201D}", detail: "On this Mac only",
                          isOn: Binding(get: { menu.wakeOn }, set: { menu.setWake($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.talkOver, title: "Talk over it", detail: "Cut in just by speaking",
                          isOn: Binding(get: { menu.talkOverOn }, set: { menu.talkOverOn = $0; menu.setTalkOver($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.liveWords, title: "Live words", detail: "See what you say in the notch",
                          isOn: Binding(get: { menu.liveWordsOn }, set: { menu.liveWordsOn = $0; menu.setLiveWords($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.stayPut, title: "Stay where I am", detail: "Agents get your words without taking your window",
                          isOn: Binding(get: { menu.stayPutOn }, set: { menu.stayPutOn = $0; menu.setStayPut($0) }))
            }
            SettingsCard(title: "Speaking to you") {
                SwitchRow(symbol: MenuSymbol.mute, title: "Mute the voice", detail: "Answers still show in the notch",
                          isOn: Binding(get: { mute.on }, set: { mute.set($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.speakUp, title: "Speak up on its own", detail: "When work finishes or ships",
                          isOn: Binding(get: { menu.speakUpOn }, set: { menu.speakUpOn = $0; menu.setSpeakUp($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.sounds, title: "Sounds", detail: "A chime when something happens",
                          isOn: Binding(get: { menu.chimesOn }, set: { menu.chimesOn = $0; menu.setChimes($0) }))
                SettingsDivider()
                ChimeVolumeRow(preview: menu.previewChime)
                    .disabled(!menu.chimesOn)
                SettingsDivider()
                SetupCatchUpRow(model: setup)
            }
        }
    }
}

/// How loud the chimes are, played once at the new level when the slider is let go so it is heard rather than guessed.
private struct ChimeVolumeRow: View {
    let preview: () -> Void
    @AppStorage(CueChimes.volumeKey) private var volume = CueChimes.defaultVolume

    private static let sliderWidth: CGFloat = 140

    var body: some View {
        SettingsRow(symbol: MenuSymbol.volume, title: "Volume", caption: "How loud the chimes are") {
            Slider(value: $volume, in: CueChimes.quietest...1) { editing in
                if !editing { preview() }
            }
            .controlSize(.small)
            .frame(width: Self.sliderWidth)
            .accessibilityLabel("Chime volume")
            .accessibilityValue("\(Int((volume * 100).rounded())) percent")
        }
    }
}

/// Saying a rule or a line, and copying what happened for support, each a row with its button at the end.
private struct HelpPage: View {
    @ObservedObject var menu: MenuModel

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: MenuSymbol.rule, title: "Say a rule",
                        caption: "Turns a sentence like \u{201C}never deploy on Fridays\u{201D} into a rule.") {
                Button("Say a rule", action: menu.sayRule)
            }
            SettingsDivider()
            SettingsRow(symbol: MenuSymbol.saySomething, title: "Say something",
                        caption: "Checks that Memnox hears and answers you.") {
                Button("Try it", action: menu.saySomething)
            }
            SettingsDivider()
            SettingsRow(symbol: MenuSymbol.copy, title: "Copy what happened",
                        caption: "Puts the recent steps on your clipboard to send to support.") {
                Button("Copy", action: menu.copyWhatHappened)
            }
            SettingsDivider()
            SettingsRow(symbol: "trash", title: "Uninstall Memnox",
                        caption: "Removes the service, its hooks in your agents, your history here, its sign ins and the app.",
                        tint: Memnox.Palette.warm) {
                Button("Uninstall", action: menu.uninstall)
            }
        }
    }
}

/// The page as Vorssaint sets its panels: solid, inset on the window's glass with rounded corners and one even grey
/// edge all round, so it stands apart from the sidebar.
private struct PagePanel: ViewModifier {
    private static let radius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        content
            .background(Memnox.Palette.background, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
    }
}
