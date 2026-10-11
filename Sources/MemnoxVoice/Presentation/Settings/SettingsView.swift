import AppKit
import SwiftUI

/// The one Memnox window: a sidebar of glass on the left with the pages in their groups and the person at the foot, and
/// the chosen page on its own rounded panel to the right, light or dark as the Mac is set.
struct SettingsView: View {
    @ObservedObject var models: SettingsModels
    @ObservedObject var navigation: SettingsNavigation
    /// Closes the window, for Escape.
    let close: () -> Void

    private enum Layout {
        static let sidebarWidth: CGFloat = 230
        static let pagePadding: CGFloat = 32
        /// Clears the window's traffic lights, which sit over the sidebar's top.
        static let titlebarRoom: CGFloat = 52
        static let pageWidth: CGFloat = 760
        /// The page's panel sits this far in from the window's top, right and bottom, as a sheet set on glass.
        static let panelInset: CGFloat = 10
        static let panelRadius: CGFloat = 16
    }

    /// The sidebar's glass tint: dark graphite in the dark and soft grey in the light, neutral rather than blue, deep
    /// enough that the desktop only shades it.
    private enum Slate {
        static let top = Color(light: 0xF0F0F2, dark: 0x2C2D31)
        static let bottom = Color(light: 0xE6E6E9, dark: 0x16171A)
        static let strength = 0.78
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $navigation.page, name: models.setup?.name ?? "")
                .frame(width: Layout.sidebarWidth)
                .padding(.top, Layout.titlebarRoom)
                .frame(maxHeight: .infinity, alignment: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
                    if navigation.page != .overview { SettingsPageHeader(page: navigation.page) }
                    page
                }
                .frame(maxWidth: Layout.pageWidth, alignment: .leading)
                .padding(Layout.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(
                RoundedRectangle(cornerRadius: Layout.panelRadius, style: .continuous)
                    .fill(Memnox.Palette.background)
                    .overlay(RoundedRectangle(cornerRadius: Layout.panelRadius, style: .continuous)
                        .strokeBorder(Memnox.ink(Memnox.Ink.rim), lineWidth: Memnox.Stroke.hairline))
            )
            .clipShape(RoundedRectangle(cornerRadius: Layout.panelRadius, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 2)
            .padding([.top, .bottom, .trailing], Layout.panelInset)
        }
        // Edge to edge, so the inset is measured from the window and not from under the title bar.
        .ignoresSafeArea()
        .background(LinearGradient(colors: [Slate.top, Slate.bottom], startPoint: .top, endPoint: .bottom)
            .opacity(Slate.strength).ignoresSafeArea())
        .background(Glass(material: .sidebar, alwaysDark: false).ignoresSafeArea())
        .background(escapeKey)
        .task(id: models.setup.map(ObjectIdentifier.init)) { await models.setup?.check() }
    }

    @ViewBuilder private var page: some View {
        if let menu = models.menu, let setup = models.setup {
            switch navigation.page {
            case .overview: OverviewPage(menu: menu, setup: setup, team: models.team, home: models.home, go: go)
            case .profile: SetupYouCard(model: setup)
            case .team:
                if let team = models.team { TeamPage(team: team) }
            case .connection: SetupMacCard(model: setup)
            case .phones: PhonesPage(menu: menu, setup: setup)
            case .voice: VoicePage(menu: menu, setup: setup)
            case .listening: ListeningPage(menu: menu, setup: setup)
            case .help: HelpPage(menu: menu)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func go(_ page: SettingsPage) { navigation.page = page }

    /// Escape closes the window the way a sheet closes, through a button no one sees.
    private var escapeKey: some View {
        Button("Close", action: close)
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

/// The wordmark, then the page list in its groups, each under a quiet label, the chosen page on a pill of glass, and the
/// person at the foot, as a sidebar of a Mac app reads.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    let name: String

    private enum Layout {
        static let rowHeight: CGFloat = 34
        static let groupGap: CGFloat = 16
        static let wordmarkHeight: CGFloat = 18
        static let chosenFill = 0.1
        static let chosenRadius: CGFloat = 10
        static let chosenShadow = 0.12
        static let avatarSide: CGFloat = 28
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.groupGap) {
            Wordmark(height: Layout.wordmarkHeight)
                .padding(.horizontal, Memnox.Spacing.regular)
                .padding(.bottom, Memnox.Spacing.medium)
            ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    if let title = group.title {
                        Text(title)
                            .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                            .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
                            .padding(.horizontal, Memnox.Spacing.regular)
                            .padding(.bottom, Memnox.Spacing.xxSmall)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(group.pages) { page in row(page) }
                }
            }
            Spacer(minLength: 0)
            person
        }
        .padding(.horizontal, Memnox.Spacing.medium)
        .padding(.bottom, Memnox.Spacing.large)
    }

    private func row(_ page: SettingsPage) -> some View {
        let chosen = selection == page
        let shape = RoundedRectangle(cornerRadius: Layout.chosenRadius, style: .continuous)
        return Button { selection = page } label: {
            HStack(spacing: MenuLayout.iconSpacing) {
                Image(systemName: page.symbol)
                    .font(.system(size: Memnox.TextSize.body, weight: .medium))
                    .frame(width: MenuLayout.iconColumnWidth)
                Text(page.title)
                    .font(Memnox.sans(Memnox.TextSize.callout, chosen ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Memnox.ink(chosen ? 1 : MenuLayout.mutedInk))
            .padding(.horizontal, Memnox.Spacing.regular)
            .frame(height: Layout.rowHeight)
            .background {
                if chosen {
                    shape.fill(Memnox.ink(Layout.chosenFill))
                        .overlay(shape.strokeBorder(Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
                        .shadow(color: .black.opacity(Layout.chosenShadow), radius: Memnox.Spacing.xSmall, y: Memnox.Stroke.hairline)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPress())
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The person at the foot, the way a Mac app signs its sidebar, and a way to their profile.
    private var person: some View {
        Button { selection = .profile } label: {
            HStack(spacing: Memnox.Spacing.medium) {
                Text(initial)
                    .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                    .foregroundStyle(Memnox.Palette.ink)
                    .frame(width: Layout.avatarSide, height: Layout.avatarSide)
                    .background(Circle().fill(Memnox.Palette.raised))
                    .overlay(Circle().strokeBorder(Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
                Text(name.isEmpty ? "You" : name)
                    .font(Memnox.sans(Memnox.TextSize.callout, .medium))
                    .foregroundStyle(Memnox.Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
            }
            .padding(.horizontal, Memnox.Spacing.regular)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuPress())
        .accessibilityLabel("Your profile")
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "M"
    }
}

/// A page's name and what it is for.
private struct SettingsPageHeader: View {
    let page: SettingsPage

    private static let titleSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            Text(page.title)
                .font(Memnox.display(Self.titleSize, .bold))
                .foregroundStyle(Memnox.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(page.subtitle)
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
        }
    }
}

/// The phones: pairing one, then the ones already paired with what each may do.
private struct PhonesPage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            SetupPhoneCard(model: setup)
            if !menu.devices.isEmpty {
                VStack(spacing: 0) {
                    ForEach(menu.devices) { device in
                        if device.id != menu.devices.first?.id { MenuDivider() }
                        DeviceRow(device: device, revoke: { menu.revoke(device) }, letDrive: { on in menu.letDrive(device, on) })
                    }
                }
                .padding(.vertical, Memnox.Spacing.xSmall)
                .surface()
            }
            if setup.serverPairing != nil { SetupServerCard(model: setup) }
        }
    }
}

/// Who thinks for the voice and which Kokoro voice speaks, then the Mac's own voice as the other choice.
private struct VoicePage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            SetupVoiceCard(model: setup)
            VoiceMenuRow(choice: menu.voiceChoice, kokoroVoice: menu.kokoroVoice, pick: pick)
                .padding(.vertical, Memnox.Spacing.xSmall)
                .surface()
        }
    }

    /// The Mac's own voice by its tag, and any Kokoro voice saved first so the chosen one is what speaks.
    private func pick(_ tag: String) {
        guard tag != VoiceChoice.mac else {
            menu.voiceChoice = VoiceChoice.mac
            menu.chooseVoice(VoiceChoice.mac)
            return
        }
        KokoroVoice.choose(tag)
        menu.kokoroVoice = tag
        menu.voiceChoice = VoiceChoice.kokoro
        menu.chooseVoice(VoiceChoice.kokoro)
        Task { await setup.voiceChanged() }
    }
}

/// The switches for when Memnox listens and speaks up, with catching up after time away.
private struct ListeningPage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            SwitchRow(symbol: MenuSymbol.wake, title: "Wake when I say \u{201C}Memnox\u{201D}", detail: "On this Mac only",
                      isOn: Binding(get: { menu.wakeOn }, set: { menu.setWake($0) }))
            MenuDivider()
            SwitchRow(symbol: MenuSymbol.speakUp, title: "Speak up on its own", detail: "When work finishes or ships",
                      isOn: Binding(get: { menu.speakUpOn }, set: { menu.speakUpOn = $0; menu.setSpeakUp($0) }))
            MenuDivider()
            SwitchRow(symbol: MenuSymbol.talkOver, title: "Talk over it", detail: "Cut in just by speaking",
                      isOn: Binding(get: { menu.talkOverOn }, set: { menu.talkOverOn = $0; menu.setTalkOver($0) }))
            MenuDivider()
            SwitchRow(symbol: MenuSymbol.sounds, title: "Sounds", detail: "A chime when something happens",
                      isOn: Binding(get: { menu.chimesOn }, set: { menu.chimesOn = $0; menu.setChimes($0) }))
            MenuDivider()
            SwitchRow(symbol: MenuSymbol.liveWords, title: "Live words", detail: "See what you say in the notch",
                      isOn: Binding(get: { menu.liveWordsOn }, set: { menu.liveWordsOn = $0; menu.setLiveWords($0) }))
            MenuDivider()
            SwitchRow(symbol: MenuSymbol.stayPut, title: "Stay where I am", detail: "Agents get your words without taking your window",
                      isOn: Binding(get: { menu.stayPutOn }, set: { menu.stayPutOn = $0; menu.setStayPut($0) }))
            MenuDivider()
            SetupCatchUpRow(model: setup)
        }
        .padding(.vertical, Memnox.Spacing.xSmall)
        .surface()
    }
}

/// Saying a rule or a line, and copying what happened for support.
private struct HelpPage: View {
    @ObservedObject var menu: MenuModel

    var body: some View {
        VStack(spacing: Memnox.Spacing.xxSmall) {
            MenuRow(symbol: MenuSymbol.rule, title: "Say a rule", action: menu.sayRule)
            MenuRow(symbol: MenuSymbol.saySomething, title: "Say something", action: menu.saySomething)
            MenuRow(symbol: MenuSymbol.copy, title: "Copy what happened", action: menu.copyWhatHappened)
        }
        .padding(Memnox.Spacing.xSmall)
        .surface()
    }
}
