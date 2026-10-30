import Foundation
import MemnoxVoiceCore
import SwiftUI

/// The rules and progress for the views: redrawn whenever the core's studio changes, with the line the last press
/// ended in.
@MainActor
final class StudioScreen: ObservableObject {
    let studio: Studio
    /// Bumped when the studio changes, so every view reading it is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the page until the next one.
    @Published var note: String?

    init(studio: Studio) {
        self.studio = studio
        studio.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    func said(_ outcome: StudioOutcome) {
        note = StudioNotes.line(outcome, proposed: "Waiting for you on the island: confirm it with Touch ID and it goes in force.")
    }

    /// Runs one press and says how it ended.
    func press(_ work: @escaping (Studio) async -> StudioOutcome) {
        Task { said(await work(studio)) }
    }
}

/// The activity for the views, redrawn whenever a page arrives or a decision opens.
@MainActor
final class ActivityScreen: ObservableObject {
    let activity: Activity
    @Published private(set) var tick = 0
    @Published var note: String?

    init(activity: Activity) {
        self.activity = activity
        activity.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }
}

/// The agents for the views, redrawn whenever the core's list changes.
@MainActor
final class AgentsScreen: ObservableObject {
    let agents: Agents
    @Published private(set) var tick = 0
    @Published var note: String?

    init(agents: Agents) {
        self.agents = agents
        agents.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    func press(_ work: @escaping (Agents) async -> StudioOutcome) {
        Task { note = StudioNotes.line(await work(agents), proposed: "Waiting for you on the island: confirm it with Touch ID.") }
    }
}

enum StudioNotes {
    static func line(_ outcome: StudioOutcome, proposed: String) -> String {
        switch outcome {
        case .proposed: proposed
        case .failed(let why): why
        case .done(let line): line
        }
    }

    /// A day as this Mac writes one, from the runtime's ISO 8601 moment; the moment itself when it does not read.
    static func day(_ iso: String) -> String {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = precise.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func moment(_ iso: String) -> String {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = precise.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

extension Tone {
    init(_ tone: StudioTone) {
        switch tone {
        case .good: self = .good
        case .attention: self = .attention
        case .bad: self = .bad
        case .quiet: self = .quiet
        }
    }

    /// The colour an effect is drawn in: green goes ahead, amber waits, red is refused.
    init(effect: String) {
        self.init(StudioLines.tone(effect))
    }
}

/// The line a press ended in, above the page until the next press.
struct NoteBanner: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ShellMetrics.rowPaddingH)
                .padding(.vertical, ShellMetrics.rowPaddingV)
                .background(Memnox.Palette.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                    .strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// A row whose title is a name a machine wrote, such as git.push, set in the code face.
struct CodeRow<Leading: View, Trailing: View>: View {
    let title: String
    var caption: String?
    var chosen = false
    var action: (() -> Void)?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        if let action {
            Button(action: action) { face.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .hoverLight(radius: 0, inset: 0)
                .accessibilityAddTraits(chosen ? .isSelected : [])
        } else {
            face
        }
    }

    private var face: some View {
        HStack(spacing: Memnox.Spacing.large) {
            leading
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(title)
                    .font(Memnox.mono(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Palette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Memnox.Spacing.medium)
            trailing
        }
        .padding(.horizontal, ShellMetrics.rowPaddingH)
        .padding(.vertical, ShellMetrics.rowPaddingV)
        .background(chosen ? Memnox.Palette.hover : Color.clear)
    }
}

/// Muted words under a block, wrapped rather than cut.
struct QuietLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
