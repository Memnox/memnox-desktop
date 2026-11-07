import { describe, expect, it } from 'vitest';
import { Projects } from '../src/core/application/projects';
import { RequestIds } from '../src/core/application/request-ids';
import { appliedLine, projectNote } from '../src/core/domain/project-lines';
import { ScriptedDaemon } from './doubles';

const nothing = { written: [], removed: [], kept: ['AGENTS.md'], governed: [], missing: [] };
const wrote = { written: ['CLAUDE.md'], removed: [], kept: [], governed: [], missing: [] };

describe('what an Apply comes to', () => {
  it('is up to date when the runtime had nothing to change, as the Mac says it', async () => {
    const projects = new Projects(new ScriptedDaemon({ 'project-apply': (request) => [{ id: request.id, ok: true, projectApplied: nothing }] }), new RequestIds());
    const outcome = await projects.apply('prj_1');
    expect(outcome).toEqual({ kind: 'up-to-date', note: appliedLine(nothing) });
    expect(projectNote(outcome, 'Windows Hello')).toBe(appliedLine(nothing));
  });

  it('is done when something was written, and waits on the island before it is ever up to date', async () => {
    const done = new Projects(new ScriptedDaemon({ 'project-apply': (request) => [{ id: request.id, ok: true, projectApplied: wrote }] }), new RequestIds());
    expect((await done.apply('prj_1')).kind).toBe('done');
    const waiting = new Projects(new ScriptedDaemon({ 'project-apply': (request) => [{ id: request.id, ok: true, proposed: 'prp_1', projectApplied: nothing }] }), new RequestIds());
    expect((await waiting.apply('prj_1')).kind).toBe('proposed');
  });
});
