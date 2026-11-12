import MemnoxVoiceCore
import SwiftUI

extension Tone {
    /// Green where Memnox stops or checks it, amber where it only asks or sees, red where it is outside.
    init(_ level: CapabilityLevel) {
        switch level {
        case .enforced, .mediated: self = .good
        case .advisory, .observed: self = .attention
        case .noEvidence: self = .bad
        }
    }
}

/// A level in its plain words and its colour, the same pill on every screen.
struct LevelPill: View {
    let level: CapabilityLevel

    var body: some View {
        StatusWord(Tone(level), CapabilityLevelLines.plain(level))
            .help(CapabilityLevelLines.technical(level))
    }
}

/// A connection as a pill: who it is and how sure Memnox is through it.
struct ConnectionPill: View {
    let connection: AgentConnection

    var body: some View {
        let level = CapabilityLevelLines.headline(connection)
        HStack(spacing: Memnox.Spacing.small) {
            BrandLogo(agent: connection.agentKind ?? connection.kind, name: connection.agentKind ?? connection.kind, size: Self.logo)
            LevelPill(level: level)
        }
        .help("\(CapabilityLevelLines.connectionKind(connection)), \(CapabilityLevelLines.status(connection).lowercased())")
        .accessibilityElement(children: .combine)
    }

    private static let logo: CGFloat = 16
}

/// How sure Memnox is of each thing an agent does, in plain words, with the technical names folded under Advanced.
struct CapabilityStrip: View {
    let levels: CapabilityLevels
    @State private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            ForEach(CapabilityLevelLines.rows(levels)) { row($0) }
            ForEach(CapabilityLevelLines.seamRows(levels)) { row($0) }
            DisclosureGroup("Advanced", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    ForEach(CapabilityLevelLines.rows(levels) + CapabilityLevelLines.seamRows(levels)) { each in
                        Text(each.technical)
                            .font(Memnox.Console.code(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.muted)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, Memnox.Spacing.xSmall)
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
            .foregroundStyle(Memnox.Console.muted)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How sure Memnox is")
    }

    private func row(_ row: CapabilityLevelLines.Row) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(row.title)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.foreground)
            Spacer(minLength: Memnox.Spacing.medium)
            LevelPill(level: row.level)
        }
    }
}
