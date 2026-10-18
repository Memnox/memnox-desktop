/** Hints only help the recognizer while they are few, so a long list waters down the names it most needs. */
export const MOST_RECOGNIZER_HINTS = 100;

/**
 * The hints to give the recognizer, in order of need, ported from `RecognizerHints.swift`: the names said
 * most, then this machine's own, then the rest. Each once, whatever its case, and never more than it weighs well.
 */
export function chosenHints(lists: readonly (readonly string[])[], most = MOST_RECOGNIZER_HINTS): string[] {
  const seen = new Set<string>();
  const chosen: string[] = [];
  for (const hint of lists.flat()) {
    const word = hint.trim();
    if (word === '' || seen.has(word.toLowerCase())) continue;
    seen.add(word.toLowerCase());
    chosen.push(word);
    if (chosen.length === most) break;
  }
  return chosen;
}

/** The names in no dictionary that people say most, misheard without a hint; the Mac's `firstRecognizerHints`. */
export const FIRST_RECOGNIZER_HINTS: readonly string[] = [
  'Memnox', 'Claude Code', 'Codex', 'Cursor', 'VS Code', 'Visual Studio Code', 'iTerm', 'Hermes', 'ChatGPT',
  'git status', 'git push', 'npm', 'kubectl', 'Railway', 'Vercel',
  'GitHub', 'Linear', 'Slack', 'pull request', 'repository', 'ticket', 'Jira', 'Notion', 'Gmail',
];
