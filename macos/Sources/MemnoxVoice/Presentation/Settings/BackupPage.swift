import AppKit
import MemnoxVoiceCore
import SwiftUI
import UniformTypeIdentifiers

/// Backing up what was set up on this Mac and putting it back. The runtime seals the archive and never holds the
/// passphrase; putting one back is only proposed here, and holds once signed with Touch ID on the island.
struct BackupPage: View {
    let backup: Backup

    var body: some View {
        CreateBackupCard(backup: backup)
        RestoreBackupCard(backup: backup)
    }
}

private enum BackupLayout {
    static let fileListHeight: CGFloat = 180
}

/// "Made 30 October 2026 at 12:00", in this Mac's own way of writing a date.
private func madeLine(_ createdAt: String) -> String {
    let stamp = ISO8601DateFormatter()
    stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = stamp.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt) else { return "Made \(createdAt)" }
    return "Made \(date.formatted(date: .long, time: .shortened))"
}

private struct CreateBackupCard: View {
    let backup: Backup
    @State private var passphrase = ""
    @State private var again = ""
    @State private var ledger = false
    @State private var busy = false
    @State private var problem: String?
    @State private var made: (archive: String, summary: BackupSummary)?
    @State private var copied = false

    var body: some View {
        SettingsCard(title: "Make a backup") {
            Muted("Rules, the MCP Hub, skills, projects and memory, sealed under a passphrase. No secret is ever put in it.")
            PassphraseField(label: "Passphrase", value: $passphrase, submit: nil)
            PassphraseField(label: "The same passphrase again", value: $again) { create() }
            SettingsRow(symbol: "clock.arrow.circlepath", title: "Include the ledger", caption: BackupLines.ledgerLine) {
                Toggle("", isOn: $ledger)
                    .toggleStyle(MemnoxSwitch())
                    .labelsHidden()
                    .accessibilityLabel("Include the ledger")
            }
            if let problem { ProblemLine(problem) }
            Button(busy ? "Sealing" : "Create backup", systemImage: "archivebox", action: create)
                .buttonStyle(KitButton(kind: .primary))
                .disabled(busy)
            if let made {
                SettingsDivider(full: true)
                SettingsRow(symbol: "archivebox", title: madeLine(made.summary.createdAt), caption: BackupLines.summaryLine(made.summary)) {
                    HStack(spacing: Memnox.Spacing.medium) {
                        Button(copied ? "Copied" : "Copy", systemImage: "doc.on.doc") { copy(made.archive) }
                            .buttonStyle(KitButton(kind: .secondary))
                        Button("Save as a file", systemImage: "square.and.arrow.down") { save(made.archive, made.summary) }
                            .buttonStyle(KitButton(kind: .secondary))
                    }
                }
                Muted(BackupLines.keepApartLine)
            }
        }
    }

    private func create() {
        problem = BackupLines.passphraseProblem(passphrase, again: again)
        guard problem == nil, !busy else { return }
        busy = true
        let typed = passphrase, carry = ledger
        Task {
            let outcome = await backup.create(passphrase: typed, ledger: carry)
            busy = false
            switch outcome {
            case .failed(let why): problem = why
            case .done(let archive, let summary):
                // The passphrase is never kept past the press that used it.
                passphrase = ""
                again = ""
                copied = false
                made = (archive, summary)
            }
        }
    }

    private func copy(_ archive: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(archive, forType: .string)
        copied = true
    }

    /// Finder's own save panel, named by the day it was made so a folder of them sorts.
    private func save(_ archive: String, _ summary: BackupSummary) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = BackupLines.archiveFileName(summary.createdAt)
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try archive.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            problem = "Memnox could not save it there: \(error.localizedDescription)"
        }
    }
}

private struct RestoreBackupCard: View {
    let backup: Backup
    @State private var archive: (name: String, text: String)?
    @State private var passphrase = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var proposed: BackupSummary?

    var body: some View {
        SettingsCard(title: "Put a backup back") {
            Muted("Choose the file and type its passphrase. Memnox reads what it holds and asks for your signature with Touch ID on the island before it puts anything back.")
            HStack(spacing: Memnox.Spacing.large) {
                Button("Choose a file", systemImage: "doc.badge.arrow.up", action: choose)
                    .buttonStyle(KitButton(kind: .secondary))
                Text(archive?.name ?? "No file chosen")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            PassphraseField(label: "Its passphrase", value: $passphrase) { restore() }
            if let problem { ProblemLine(problem) }
            Button(busy ? "Reading" : "Restore", systemImage: "arrow.uturn.backward", action: restore)
                .buttonStyle(KitButton(kind: .primary))
                .disabled(busy)
            if let proposed {
                SettingsDivider(full: true)
                VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                    Text(BackupLines.restoreWaitsLine)
                        .font(Memnox.sans(Memnox.TextSize.body))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Muted("\(madeLine(proposed.createdAt)): \(BackupLines.summaryLine(proposed))")
                    ScrollView {
                        VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                            ForEach(proposed.files, id: \.self) { file in
                                Text(file)
                                    .font(Memnox.mono(Memnox.TextSize.micro))
                                    .foregroundStyle(Memnox.Palette.muted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: BackupLayout.fileListHeight)
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.prompt = "Choose"
        proposed = nil
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            archive = (url.lastPathComponent, try String(contentsOf: url, encoding: .utf8))
            problem = nil
        } catch {
            archive = nil
            problem = "Memnox could not read that file: \(error.localizedDescription)"
        }
    }

    private func restore() {
        guard let archive else {
            problem = "Choose the backup file first."
            return
        }
        problem = BackupLines.passphraseProblem(passphrase, again: nil)
        guard problem == nil, !busy else { return }
        busy = true
        let typed = passphrase
        Task {
            let outcome = await backup.restore(archive: archive.text, passphrase: typed)
            busy = false
            switch outcome {
            case .failed(let why): problem = why
            case .proposed(_, let summary):
                passphrase = ""
                proposed = summary
            }
        }
    }
}

/// A passphrase typed out of sight, at least ten characters, which Return sends when the form allows it.
private struct PassphraseField: View {
    let label: String
    @Binding var value: String
    let submit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text(label)
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Palette.muted)
            SecureField("At least \(BackupLines.shortestPassphrase) characters", text: $value)
                .kitField()
                .onSubmit { submit?() }
                .accessibilityLabel(label)
        }
    }
}

private struct ProblemLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Palette.destructive)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct Muted: View {
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
