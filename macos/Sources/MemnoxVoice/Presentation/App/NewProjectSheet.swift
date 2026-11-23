import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What a new project sheet opens with: empty from New project, or an example's name and care from Start like this.
struct NewProjectStart: Identifiable, Equatable {
    var name = ""
    var care = ProjectCare.relaxed
    var id: String { "\(name)/\(care.rawValue)" }
}

/// The answers the sheet hands back, the folder the one that cannot be skipped.
struct NewProjectAnswers {
    let folder: String
    let name: String
    let care: ProjectCare
    let know: [String]
}

/// Making a project as three questions anyone can answer and one optional box, each with a sensible answer already
/// there: what the work is called, where it lives, how careful agents should be, and what they should always know.
struct NewProjectSheet: View {
    let start: NewProjectStart
    let close: () -> Void
    let make: (NewProjectAnswers) -> Void
    @State private var name = ""
    @State private var folder: String?
    @State private var care = ProjectCare.relaxed
    @State private var know = ""

    private enum Layout {
        static let knowHeight: CGFloat = 96
        static let radio: CGFloat = 14
        static let ring: CGFloat = 2
    }

    var body: some View {
        SkillSheetFrame(title: NewProject.title) {
            question(NewProject.nameQuestion) {
                TextField(NewProject.namePrompt, text: $name).kitField()
            }
            question(NewProject.placeQuestion, line: NewProject.placeLine) {
                HStack(spacing: Memnox.Spacing.medium) {
                    Button(folder == nil ? ProjectContext.chooseTitle : "Choose another", systemImage: "folder", action: choose)
                        .buttonStyle(KitButton(kind: .secondary))
                    if let folder {
                        Text(folder)
                            .font(Memnox.Console.code(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Console.foreground)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                ProjectMuted(NewProject.noFolderLine)
            }
            question(NewProject.careQuestion) {
                ShellPanel {
                    ForEach(Array(ProjectCare.allCases.enumerated()), id: \.element) { index, each in
                        if index > 0 { ShellDivider() }
                        option(each)
                    }
                }
            }
            question(NewProject.knowQuestion, line: NewProject.knowLine) {
                TextEditor(text: $know)
                    .font(Memnox.Console.sans(Memnox.TextSize.body))
                    .frame(height: Layout.knowHeight)
                    .consoleEditor()
                    .accessibilityLabel(NewProject.knowQuestion)
            }
        } footer: {
            Spacer()
            Button("Cancel", action: close)
                .buttonStyle(KitButton(kind: .secondary))
                .keyboardShortcut(.cancelAction)
            Button(NewProject.create) {
                guard let folder else { return }
                make(NewProjectAnswers(folder: folder, name: NewProject.name(typed: name, folder: folder), care: care,
                                       know: NewProject.instructions(know)))
                close()
            }
            .buttonStyle(KitButton(kind: .primary))
            .keyboardShortcut(.defaultAction)
            .disabled(folder == nil)
        }
        .onAppear {
            name = start.name
            care = start.care
        }
    }

    private func question<Field: View>(_ title: String, line: String? = nil, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text(title)
                .font(Memnox.Console.sans(Memnox.TextSize.body, .semibold))
                .foregroundStyle(Memnox.Console.foreground)
            if let line { ProjectMuted(line) }
            field()
        }
    }

    private func option(_ level: ProjectCare) -> some View {
        let on = care == level
        return Button { care = level } label: {
            ShellRow(title: level.label, caption: level.line) {
                Circle()
                    .strokeBorder(on ? Memnox.Console.primary : Memnox.Console.muted, lineWidth: Layout.ring)
                    .background(Circle().fill(on ? Memnox.Console.primary : Color.clear))
                    .frame(width: Layout.radio, height: Layout.radio)
                    .accessibilityHidden(true)
            } trailing: {
                EmptyView()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// Finder's own panel, which also takes a typed path with Command Shift G.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = ProjectWhy.chooseLine
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path
    }
}
