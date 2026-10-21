import MemnoxVoiceCore
import SwiftUI

/// A page of the grid that does its work in the notch rather than sending the person to Settings.
enum LauncherPanel: Equatable {
    case phones
    case dictation

    var title: String {
        switch self {
        case .phones: "Phones"
        case .dictation: "Dictation"
        }
    }
}

/// One line of a launcher page: a symbol, a title over a caption, and the control at the end, drawn for the dark island.
private struct PanelRow<Accessory: View>: View {
    let symbol: String
    let title: String
    let caption: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: Memnox.Spacing.large) {
            Image(systemName: symbol)
                .font(.system(size: Memnox.TextSize.headline))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                .frame(width: PanelLayout.symbolColumn)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(title)
                    .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Color.white)
                if let caption {
                    Text(caption)
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Memnox.Spacing.large)
            accessory
        }
        .padding(.horizontal, Memnox.Spacing.large)
        .padding(.vertical, Memnox.Spacing.regular)
        .background(RoundedRectangle(cornerRadius: PanelLayout.rowCorner, style: .continuous).fill(Color.white.opacity(Memnox.Ink.faintFill)))
    }
}

private enum PanelLayout {
    static let symbolColumn: CGFloat = 22
    static let rowCorner: CGFloat = 14
    static let qrSide: CGFloat = 132
    static let quietZone: CGFloat = 8
    static let qrCorner: CGFloat = 10
    static let digitsSize: CGFloat = 24
    static let digitsTracking: CGFloat = 2
    static let digitsGroup = 3
    /// How far a switch that cannot matter right now fades.
    static let restingOpacity = 0.4
}

/// The phones paired with this Mac, each with Revoke and whether it may drive, and pairing a new one in the notch: the
/// code to scan, the digits to match, and Touch ID for the yes.
struct IslandPhonesPanel: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                pairing
                ForEach(menu.devices) { device in
                    PanelRow(symbol: MenuSymbol.phone, title: device.name, caption: drives(device) ? "Can drive this Mac" : "Paired") {
                        Toggle("Let it drive this Mac", isOn: Binding(get: { drives(device) }, set: { on in
                            if on != drives(device) { menu.letDrive(device, on) }
                        }))
                        .toggleStyle(MemnoxSwitch())
                        .labelsHidden()
                        .help(drives(device) ? "Stop it driving this Mac" : "Let it drive this Mac, with Touch ID")
                        Button("Revoke") { menu.revoke(device) }.buttonStyle(IslandButton(primary: false))
                    }
                }
                if menu.devices.isEmpty, case .idle = setup.phone {
                    Text("No phone paired yet. Pair one to talk to Memnox and answer your agents from anywhere.")
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .scrollIndicators(.hidden)
        .onAppear { menu.loadDevices() }
    }

    private func drives(_ device: Device) -> Bool { device.granted.contains(.mac) }

    @ViewBuilder private var pairing: some View {
        switch setup.phone {
        case .idle, .failed:
            PanelRow(symbol: "qrcode", title: "Pair a phone", caption: failure) {
                Button("Show code") { Task { await setup.pairPhone() } }.buttonStyle(IslandButton(primary: true))
            }
        case .opening:
            PanelRow(symbol: "qrcode", title: "Pair a phone", caption: "Getting a code") { ProgressView().controlSize(.small) }
        case .showing(let qr):
            HStack(spacing: Memnox.Spacing.xLarge) {
                if let image = QRImage.make(qr) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: PanelLayout.qrSide, height: PanelLayout.qrSide)
                        .padding(PanelLayout.quietZone)
                        .background(RoundedRectangle(cornerRadius: PanelLayout.qrCorner, style: .continuous).fill(Color.white))
                }
                Text("Scan this with the Memnox app on your iPhone.")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .checking(let phone), .approving(let phone):
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                Text(phone.name)
                    .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Color.white)
                Text(grouped(phone.code))
                    .font(.system(size: PanelLayout.digitsSize, weight: .semibold, design: .monospaced))
                    .tracking(PanelLayout.digitsTracking)
                    .foregroundStyle(Color.white)
                Text("Approve if your iPhone shows the same digits.")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                Button(isApproving ? "Waiting for Touch ID" : "Approve") { Task { await setup.approvePhone() } }
                    .buttonStyle(IslandButton(primary: true))
                    .disabled(isApproving)
            }
        case .paired(let name):
            PanelRow(symbol: "checkmark.circle.fill", title: PairingLines.paired(name), caption: nil) { EmptyView() }
        }
    }

    private var isApproving: Bool {
        if case .approving = setup.phone { return true }
        return false
    }

    private var failure: String? {
        if case .failed(let why) = setup.phone { return why }
        return "Talk to Memnox and answer your agents from your iPhone"
    }

    /// "482913" as "482 913", so six digits read at a glance.
    private func grouped(_ digits: String) -> String {
        guard digits.count > PanelLayout.digitsGroup else { return digits }
        return "\(digits.prefix(PanelLayout.digitsGroup)) \(digits.dropFirst(PanelLayout.digitsGroup))"
    }
}

/// Dictation's three switches in the notch, the same ones Settings keeps, with how to start it said once at the top.
struct IslandDictationPanel: View {
    @AppStorage(DictationKey.enabledKey) private var dictation = true
    @AppStorage(DictationStore.liveKey) private var live = true
    @AppStorage(DictationStore.polishKey) private var polish = true

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            row(MenuSymbol.dictation, "Dictate anywhere", "Hold the right Option key and speak, or tap it twice to keep going", $dictation)
            Group {
                row("text.cursor", "Type as I speak", "Words appear at the cursor while you talk", $live)
                row("sparkles", "Polish with Claude Code", "Tidies false starts, and edits selected text by voice", $polish)
            }
            .disabled(!dictation)
            .opacity(dictation ? 1 : PanelLayout.restingOpacity)
        }
    }

    private func row(_ symbol: String, _ title: String, _ caption: String, _ isOn: Binding<Bool>) -> some View {
        PanelRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: isOn).toggleStyle(MemnoxSwitch()).labelsHidden()
        }
    }
}
