import { activityLine } from './studio-lines';

/**
 * An action an agent took, said the way a person would say it, such as Changed form-parts.tsx in memnox-client,
 * so Today reads without knowing what filesystem.write means; Activity keeps the action as written. Ported from the
 * Mac's `ActivityWords`.
 */
const CHANGES = new Set(['filesystem.write', 'file.write', 'file.edit', 'file.create', 'fs.write', 'notebook.edit']);
const READS = new Set(['filesystem.read', 'file.read', 'fs.read', 'environment.read']);
const DELETES = new Set(['filesystem.delete', 'file.delete', 'fs.delete']);
const GIT_VERBS: Record<string, string> = {
  'git.push': 'Pushed',
  'git.commit': 'Saved a commit',
  'git.pull': 'Pulled',
  'git.merge': 'Merged',
  'git.checkout': 'Switched branch',
  'git.reset': 'Reset',
  'git.clone': 'Copied a repository',
};
/** Folders that sit inside a project, so the folder above the first of them names the project. */
const INSIDE_PROJECT = new Set([
  'apps', 'app', 'src', 'packages', 'lib', 'Sources', 'Tests', 'components', 'test', 'tests', 'docs',
  'cmd', 'internal', 'scripts', 'public', '.github', 'ios', 'android', 'macos', 'shared',
]);

export function activityWords(row: { operation: string; target?: string | undefined }): string {
  const target = row.target?.trim() || undefined;
  const { operation } = row;
  if (CHANGES.has(operation)) return files('Changed', target);
  if (READS.has(operation)) return files('Read', target);
  if (DELETES.has(operation)) return files('Deleted', target);
  const verb = GIT_VERBS[operation];
  if (verb !== undefined) return verb;
  switch (operation.split('.')[0]) {
    case 'shell':
    case 'process':
      return target === undefined ? 'Ran a command' : `Ran ${target.split(' ')[0]}`;
    case 'http':
    case 'web':
    case 'fetch':
      return target === undefined ? 'Reached a website' : `Reached ${host(target)}`;
    case 'mcp':
      return target === undefined ? 'Used a tool' : `Used ${target}`;
    default:
      return activityLine({ operation, ...(target === undefined ? {} : { target }) });
  }
}

function files(verb: string, target: string | undefined): string {
  if (target === undefined || !(target.startsWith('/') || target.startsWith('~'))) {
    return target === undefined ? `${verb} files` : `${verb} ${target}`;
  }
  const isFolder = target.endsWith('/') || target.endsWith('/.');
  const parts = target.split('/').filter((part) => part !== '' && part !== '.' && part !== '~');
  const name = isFolder ? undefined : parts.at(-1);
  const place = project(isFolder ? parts : parts.slice(0, -1));
  if (name !== undefined && place !== undefined) return `${verb} ${name} in ${place}`;
  if (name !== undefined) return `${verb} ${name}`;
  if (place !== undefined) return `${verb} files in ${place}`;
  return `${verb} files`;
}

/** The folder above the first one that only a project holds, else the folder the file sits in. */
function project(folders: string[]): string | undefined {
  const inside = folders.findIndex((folder, index) => index > 0 && INSIDE_PROJECT.has(folder));
  return inside > 0 ? folders[inside - 1] : folders.at(-1);
}

/** Read by hand rather than with URL, since the core is built without the DOM's types. */
function host(target: string): string {
  return /^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i.exec(target)?.[1] ?? target;
}
