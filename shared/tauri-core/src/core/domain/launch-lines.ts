import type { AgentLaunched } from '@memnox/core/wire';

/** A folder the runtime can open an agent in: absolute on Linux, on a drive or a share on Windows. */
export function isAbsoluteFolder(path: string): boolean {
  const trimmed = path.trim();
  return trimmed.startsWith('/') || /^[A-Za-z]:[\\/]/.test(trimmed) || trimmed.startsWith('\\\\');
}

/** What the Launch field says before it is sent, or undefined when the folder will do. */
export function folderProblem(path: string): string | undefined {
  if (path.trim() === '') return 'Choose the folder it opens in.';
  return isAbsoluteFolder(path) ? undefined : 'Give the whole path, from the top of the drive.';
}

/** "Opened Claude Code in /code/app, typing claude." said under the card. */
export function launchedLine(launched: AgentLaunched, name: string): string {
  return `Opened ${name} in ${launched.workingDirectory}, typing ${launched.line}.`;
}
