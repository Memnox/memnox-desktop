import { describe, expect, it } from 'vitest';
import type { SkillCalibration, SkillStatsView } from '@memnox/core/wire';
import { RequestIds } from '../src/core/application/request-ids';
import { SkillCare } from '../src/core/application/skill-care';
import { SkillsHub } from '../src/core/application/skills';
import { calibrateHint, careCounts, lineDiff, noteLine } from '../src/core/domain/skill-care-lines';
import { countedLine, foundMatching, groupedFound, homeOf, importAllTitle, importedLine, instructionsFile, matchesQuery, shortPath } from '../src/core/domain/skill-search';
import { ScriptedDaemon } from './doubles';

const stats = (change: Partial<SkillStatsView>): SkillStatsView => ({ name: 'review', uses: 0, failures: 0, refusals: 0, notes: [], recentFailures: [], ...change });

describe("a skill's use and its fixes", () => {
  it('says how a skill fared, or that it was not used', () => {
    expect(careCounts(undefined)).toBe('Not used in the last 30 days');
    expect(careCounts(stats({ uses: 1, failures: 2, refusals: 1 }))).toBe('Used once, 2 failures, 1 refusal in the last 30 days');
  });

  it('says what Calibrate builds from before it is pressed', () => {
    expect(calibrateHint(stats({}))).toContain('no fix to suggest');
    expect(calibrateHint(stats({ notes: ['a'], recentFailures: ['x', 'y'] }))).toBe('Builds a Known issues section from 1 note and 2 failures.');
  });

  it('keeps a note to one line', () => {
    expect(noteLine('  read the diff\nfirst ')).toBe('read the diff first');
    expect(noteLine('   ')).toBeUndefined();
  });

  it('marks what a suggestion keeps, adds and takes away', () => {
    expect(lineDiff(['a', 'b', 'c'], ['a', 'x', 'c']).map((line) => `${line.mark}:${line.text}`)).toEqual(['same:a', 'removed:b', 'added:x', 'same:c']);
  });

  it('accepts a suggestion through skill-put, so one reaching further waits on the island', async () => {
    const calibration = { name: 'review', section: 'Known issues', before: [], after: ['x'], draft: { name: 'review', version: '1.0.1' }, notes: 1, failures: 0 } as unknown as SkillCalibration;
    const daemon = new ScriptedDaemon({
      'skill-calibrate': (request) => [{ id: request.id, ok: true, skillCalibration: calibration }],
      'skill-put': (request) => [{ id: request.id, ok: true, proposed: 'p1' }],
    });
    const care = new SkillCare(daemon, new RequestIds());
    await care.calibrate('review');
    expect(care.calibration?.name).toBe('review');
    const outcome = await care.accept(calibration, 'project', 'site');
    expect(outcome).toEqual({ kind: 'proposed', id: 'p1' });
    expect(daemon.sent('skill-put')[0]?.skillProject).toBe('site');
    expect(care.calibration).toBeUndefined();
  });

  it('leaves the section out for a runtime that does not count skills', async () => {
    const daemon = new ScriptedDaemon({ 'skill-stats': (request) => [{ id: request.id, ok: true }] });
    const care = new SkillCare(daemon, new RequestIds());
    await care.refresh();
    expect(care.answered).toBe(false);
  });
});

describe('skills found on this computer', () => {
  const found = [
    { id: '1', name: 'zeta', agent: 'codex', kind: 'skill', path: '/home/sam/.codex/skills/zeta', tools: [], grant: 'reads', imported: false },
    { id: '2', name: 'alpha', agent: 'codex', kind: 'skill', path: '/home/sam/.codex/skills/alpha', tools: ['Bash'], grant: 'runs', imported: false },
    { id: '3', name: 'done', agent: 'claude', kind: 'skill', path: 'C:\\Users\\sam\\.claude\\skills\\done', tools: [], grant: 'reads', imported: true },
  ];
  const label = (agent: string) => (agent === 'codex' ? 'Codex' : 'Claude Code');

  it('matches every word typed, case and accents aside', () => {
    expect(matchesQuery(['higgsfield-video-explainer'], 'Higgs VIDÉO')).toBe(true);
    expect(foundMatching(found, 'bash', label).map((each) => each.name)).toEqual(['alpha']);
  });

  it('groups by agent, each agent by name, and leaves out what is in the hub', () => {
    const groups = groupedFound(foundMatching(found, '', label), label);
    expect(groups.map((group) => group.label)).toEqual(['Codex']);
    expect(groups[0]?.skills.map((each) => each.name)).toEqual(['alpha', 'zeta']);
  });

  it('writes paths from the home folder on every system', () => {
    expect(shortPath(found[0]!.path, homeOf(found[0]!.path))).toBe('~/.codex/skills/zeta');
    expect(shortPath(found[2]!.path, homeOf(found[2]!.path))).toBe('~\\.claude\\skills\\done');
    expect(instructionsFile(found[2]!)).toBe('C:\\Users\\sam\\.claude\\skills\\done\\SKILL.md');
  });

  it('says what an import all takes and came to', () => {
    expect(importAllTitle(9, true)).toBe('Import 9 shown');
    expect(countedLine(3, 12, true)).toBe('3 of 12');
    expect(importedLine({ done: 2, proposed: 1, failed: ['bad name'] })).toBe('2 skills are in the hub now. 1 waits for your signature on the island. 1 did not import: bad name');
  });

  it('imports one at a time, telling how far it has come', async () => {
    const daemon = new ScriptedDaemon({ 'skill-import': (request) => [{ id: request.id, ok: true }] });
    const hub = new SkillsHub(daemon, new RequestIds());
    const seen: number[] = [];
    const results = await hub.importAll(found.slice(0, 2), (done) => seen.push(done));
    expect(results.done).toBe(2);
    expect(seen).toEqual([1, 2]);
  });
});
