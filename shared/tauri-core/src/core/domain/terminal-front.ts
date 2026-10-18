/**
 * The Mac's `TerminalFront`: whether an agent is the program in front on a terminal. The same programs the
 * runtime and the editor extension check for, read here from the paths a terminal's own listing gives.
 */

const AGENT_PROGRAMS: readonly string[] = ['claude', 'node', 'codex', 'gemini', 'cursor-agent', 'aider', 'opencode'];
/** Folders a native install keeps an agent in; never node's, which holds shells and tools too. */
const AGENT_FOLDERS = AGENT_PROGRAMS.filter((program) => program !== 'node');
/** The agent's own folder and the versions folder inside it. */
const VERSIONED_FOLDERS = 2;
/** The mark `ps -o stat=` puts on the process group in front of its terminal. */
const FOREGROUND_MARK = '+';

/** Whether a program, by its path, is an agent; a native install runs a binary named for its version inside a folder named for the agent. */
export function isAgentProgram(path: string): boolean {
  const parts = path
    .toLowerCase()
    .split(/[/\\]/)
    .filter((part) => part !== '');
  const last = parts.at(-1);
  if (last === undefined) return false;
  if (AGENT_PROGRAMS.includes(last.replace(/\.exe$/, ''))) return true;
  return parts.slice(0, -1).slice(-VERSIONED_FOLDERS).some((folder) => AGENT_FOLDERS.includes(folder));
}

/** True when a line of `ps -o stat=,comm= -t <tty>` is an agent marked as in front, so the session lives in that terminal. */
export function agentInFront(listing: string): boolean {
  return listing.split('\n').some((line) => {
    const fields = line.trim().split(/\s+/);
    const stat = fields[0];
    if (stat === undefined || !stat.includes(FOREGROUND_MARK) || fields.length < 2) return false;
    return isAgentProgram(fields.slice(1).join(' '));
  });
}
