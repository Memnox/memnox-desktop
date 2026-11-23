import type { ProjectDraft, ProjectView } from '@memnox/core/wire';
import { draftOf } from './project-lines';

/**
 * Making a project as three questions anyone can answer and one optional box, the Mac's `NewProject`: what the work
 * is called, where it lives, how careful agents should be there, and what agents there should always know.
 */
export const NewProjectLines = {
  title: 'New project',
  nameQuestion: 'What is this work called?',
  namePrompt: 'Such as Website, Invoicing or Support inbox',
  placeQuestion: 'Where does it live?',
  placeLine: 'The folder on this computer its files are in. Agents working there count as working on it.',
  noFolderLine: 'Work with no folder, done by cloud or no code agents, is a shared project in Memnox Cloud.',
  careQuestion: 'How careful should agents be here?',
  knowQuestion: 'Anything agents here should always know?',
  knowLine: 'One thing per line, such as: refunds over 500 dollars go to finance. You can skip this.',
  create: 'Make the project',
  chooseAnother: 'Choose another',
} as const;

/** The name typed, else the folder's own name, so skipping the first question still names it. */
export function newProjectName(typed: string, folder: string): string {
  const trimmed = typed.trim();
  if (trimmed !== '') return trimmed;
  return folder.split(/[\\/]/).filter((part) => part !== '').at(-1) ?? folder;
}

/** What agents should always know, one line each, blank lines dropped. */
export function knowLines(text: string): string[] {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line !== '');
}

/** The manifest under the name answered, everything else the folder already had kept; undefined where it is the same. */
export function namedDraft(project: Parameters<typeof draftOf>[0] & Pick<ProjectView, 'name'>, name: string): ProjectDraft | undefined {
  return name.trim() === '' || name.trim() === project.name ? undefined : { ...draftOf(project), name: name.trim() };
}

/** Said once what agents should know is kept. */
export function rememberedLine(count: number): string {
  return count === 1 ? 'Agents here will know that from now on.' : `Agents here will know those ${count} things from now on.`;
}
