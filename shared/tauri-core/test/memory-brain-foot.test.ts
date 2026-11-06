import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { LAYER_INK } from '../src/core/domain/memory-arms/arms-ink';
import { attentionNodes, drawnModel, drawnStats, legendRows, NOTHING_CUT } from '../src/core/domain/memory-arms/arms-legend';
import type { ArmsItem, ArmsModel } from '../src/core/domain/memory-arms/arms-model';
import type { MemoryMap } from '../src/core/domain/memory-arms/arms-node';
import {
  ASSEMBLED,
  isAssembled,
  opened,
  playhead,
  poseAt,
  sample,
  scrubTour,
  sectionAt,
  sectionNumber,
  toggleTour,
  TOUR_LENGTH,
  TOUR_REACH,
  TOUR_SECTIONS,
  tourSeconds,
  type TourPose,
} from '../src/core/domain/memory-arms/arms-tour';
import {
  BRAIN_KEYS,
  BRAIN_SPEED,
  BRAIN_VIEWS,
  brainGrowth,
  BrainFootLines,
  BrainLegendLines,
  BrainViewLines,
  layerWord,
  TourLines,
  tourDetail,
  tourName,
  workspaceFoot,
  WorkspaceFootLines,
} from '../src/core/domain/memory-brain-lines';

/**
 * The brain's foot, its legend and its tour, held to the Mac's own `MemoryMapView.swift`, `BrainTour.swift` and
 * design system, so a word, a key or a measure that drifts on either side fails here.
 */
const read = (path: string) => readFileSync(new URL(`../../../macos/Sources/${path}`, import.meta.url), 'utf8');
const view = read('MemnoxVoice/Presentation/App/MemoryMapView.swift');
const tour = read('MemnoxVoiceCore/Domain/Memory/BrainTour.swift');
const motion = read('MemnoxVoiceCore/Domain/Memory/BrainMotion.swift');
const design = read('MemnoxVoice/Presentation/DesignSystem.swift');
const live = read('MemnoxVoiceCore/Domain/Memory/WorkspaceLiveLines.swift');
const pulled = read('MemnoxVoiceCore/Domain/Memory/WorkspaceMemoryLines.swift');
const css = readFileSync(new URL('../src/ui/styles.css', import.meta.url), 'utf8');

const onMac = (text: string) => text.replace(/this computer/g, 'this Mac').replace(/This computer/g, 'This Mac');
const said = (swift: string, text: string) => swift.includes(`"${onMac(text)}"`);
const swiftNumber = (swift: string, name: string) => Number(new RegExp(`static let ${name}(?:: CGFloat)? = (-?[\\d.]+)`).exec(swift)?.[1]);
const token = (name: string) => Number(new RegExp(`--${name}: (-?[\\d.]+)px;`).exec(css)?.[1]);

describe('the words along the brain foot', () => {
  it('says the hints, the pills and their help as the Mac does', () => {
    for (const text of [BrainFootLines.leftHint, BrainFootLines.orbsHint, BrainFootLines.rightHint, BrainFootLines.cinemaHelp, BrainFootLines.tourStill, BrainFootLines.leaveCinema]) {
      expect(said(view, text), text).toBe(true);
    }
    for (const title of [BrainFootLines.search, BrainFootLines.replay, BrainFootLines.cinema, BrainFootLines.tour, BrainFootLines.fit]) expect(view).toContain(`"${title}"`);
    expect(view).toContain('"Search the brain, or press \\(BrainWords.searchKey)"');
    expect(BrainFootLines.searchHelp).toBe('Search the brain, or press /');
    expect(view).toContain('"Fly the layers in again from the core outward, or press \\(BrainWords.replayKey)"');
    expect(BrainFootLines.replayHelp).toBe('Fly the layers in again from the core outward, or press R');
    expect(view).toContain('"Take the brain apart layer by layer and put it back, or press \\(BrainWords.tourKey)"');
    expect(view).toContain('"Fit the whole brain on screen, or press \\(MapWords.fitKey)"');
    expect(BrainFootLines.fitHelp).toBe('Fit the whole brain on screen, or press F');
    for (const label of [BrainFootLines.zoomOut, BrainFootLines.zoomIn, BrainFootLines.zoom]) expect(view).toContain(`"${label}"`);
  });

  it('counts the growth card and the quiet lines in the Mac words', () => {
    expect(view).toContain('"memory in the brain", "memories in the brain"');
    expect(BrainFootLines.inTheBrain(1)).toBe('1 memory in the brain');
    expect(BrainFootLines.inTheBrain(4)).toBe('4 memories in the brain');
    expect(view).toContain('"\\(verified) verified, \\(total - verified) still to settle"');
    expect(BrainFootLines.verified(3, 5)).toBe('3 verified, 2 still to settle');
    expect(said(view, BrainFootLines.nothingNeedsYou)).toBe(true);
    expect(said(view, BrainFootLines.everythingHidden)).toBe(true);
  });

  it('presses the Mac keys', () => {
    for (const [name, key] of [['replayKey', BRAIN_KEYS.replay], ['tourKey', BRAIN_KEYS.tour], ['motionKey', BRAIN_KEYS.motion], ['searchKey', BRAIN_KEYS.search], ['fitKey', BRAIN_KEYS.fit], ['centerKey', BRAIN_KEYS.center], ['pauseKey', BRAIN_KEYS.pause]] as const) {
      expect(view, name).toContain(`static let ${name} = "${key}"`);
    }
    expect(view).toContain('static let pressZoom = 1.2');
  });

  it('names the views and the motion controls as the Mac does, at its speeds', () => {
    for (const each of BRAIN_VIEWS) expect(view).toContain(`"${each.title}"`);
    expect(view).toContain('"Motion \\(motionOn ? "on" : "off"), or press \\(MapWords.pauseKey)"');
    expect(BrainViewLines.motion(true)).toBe('Motion on, or press Space');
    expect(said(view, BrainViewLines.motionSpeed)).toBe(true);
    expect(said(view, BrainViewLines.label)).toBe(true);
    expect([swiftNumber(motion, 'slowest'), swiftNumber(motion, 'quickest'), swiftNumber(motion, 'normalSpeed')]).toEqual([BRAIN_SPEED.slowest, BRAIN_SPEED.quickest, BRAIN_SPEED.normal]);
  });
});

describe('the legend', () => {
  it('heads and labels its rows in the Mac words', () => {
    for (const text of [BrainLegendLines.areas, BrainLegendLines.layers, BrainLegendLines.attentionOnly, BrainLegendLines.allLabels, BrainLegendLines.label, BrainLegendLines.lights, BrainLegendLines.routinesLater]) {
      expect(said(view, text), text).toBe(true);
    }
    expect(view).toContain('"Hide \\(name)"');
    expect(BrainLegendLines.hide('Rules')).toBe('Hide Rules');
    for (const layer of ['skill', 'rule', 'app'] as const) expect(view).toContain(`"${layerWord(layer)}"`);
  });

  const item = (id: string, layer: ArmsItem['layer'], extra: Partial<ArmsItem> = {}): ArmsItem => ({ id, layer, label: id, theta: 0, f: 0.5, phi: 0, words: id, ...extra });
  const model: ArmsModel = {
    items: [
      item('hub:notes', 'memory', { hub: true, sector: 'notes', holds: 2 }),
      item('fact:a', 'memory', { sector: 'notes', nodeId: 'fact:a', kind: 'memory' }),
      item('doc:a', 'memory', { sector: 'notes', nodeId: 'doc:a', kind: 'document' }),
      item('fact:b', 'memory', { sector: 'slack', nodeId: 'fact:b', kind: 'memory' }),
      item('skill:tidy', 'skill'),
      item('rule:ask', 'rule'),
      item('app:slack', 'app'),
    ],
    sectors: [
      { key: 'notes', label: 'Notes', count: 3, ink: '#4C8DFF', x: 0, y: 0, r: 0.2, theta: 0, hubId: 'hub:notes' },
      { key: 'slack', label: 'Slack', count: 1, ink: '#F5C542', x: 0.4, y: 0, r: 0.1, theta: 1, hubId: 'hub:slack' },
    ],
    memories: 2,
    rings: { envelope: 0.8, rules: 0.9, apps: 1.1 },
    empty: false,
  };
  const map: MemoryMap = {
    nodes: [
      { id: 'fact:a', kind: 'memory', label: 'a', status: 'settled' },
      { id: 'doc:a', kind: 'document', label: 'a.md' },
      { id: 'fact:b', kind: 'memory', label: 'b', status: 'recent' },
    ],
    edges: [{ id: 'e', from: 'fact:a', to: 'doc:a', kind: 'derives' }],
  };

  it('lists each area in packing order and each outer layer present, as the Mac legend does', () => {
    const rows = legendRows(model);
    expect(rows.areas.map((row) => [row.key, row.count])).toEqual([['notes', 3], ['slack', 1]]);
    expect(rows.layers).toEqual([{ layer: 'skill', count: 1 }, { layer: 'rule', count: 1 }, { layer: 'app', count: 1 }]);
  });

  it('takes an area or a layer off without moving what stays', () => {
    const drawn = drawnModel(model, map, { areas: new Set(['notes']), layers: new Set(['rule']) });
    expect(drawn.items.map((each) => each.id)).toEqual(['fact:b', 'skill:tidy', 'app:slack']);
    expect(drawn.items.find((each) => each.id === 'fact:b')?.theta).toBe(0);
    expect(drawn.sectors.map((each) => each.key)).toEqual(['slack']);
    expect(drawnModel(model, map, NOTHING_CUT)).toBe(model);
  });

  it('keeps only what needs attention with everything one line from it, and no outer layer', () => {
    const drawn = drawnModel(model, map, { areas: new Set(), layers: new Set(), attention: new Set(['fact:a']) });
    expect(drawn.items.map((each) => each.id)).toEqual(['fact:a', 'doc:a']);
    expect(drawnModel(model, map, { areas: new Set(), layers: new Set(), attention: new Set() }).empty).toBe(true);
  });

  it('asks for attention on what waits, conflicts or ran out, as MemoryGroups.attentionStatuses', () => {
    const fact = (id: string, status: string) => ({ id, status }) as never;
    const ids = attentionNodes({ items: [fact('1', 'candidate'), fact('2', 'verified'), fact('3', 'conflicting'), fact('4', 'outdated'), fact('5', 'rejected')] });
    expect([...ids]).toEqual(['fact:1', 'fact:3', 'fact:4']);
  });

  it('counts the drawn facts, the sources read and the tiles round the outside, and the lines between drawn marks', () => {
    expect(drawnStats(model, map, ['notes', 'slack', undefined], NOTHING_CUT)).toEqual({ memories: 2, sources: 4, connections: 1 });
    const cut = { areas: new Set(['notes']), layers: new Set<'app'>(['app']) };
    expect(drawnStats(drawnModel(model, map, cut), map, ['notes', 'slack'], cut)).toEqual({ memories: 1, sources: 1, connections: 0 });
  });
});

describe('the growth card', () => {
  const counts = (verified: number, candidate: number) => ({ counts: { candidate, verified, conflicting: 0, outdated: 0, rejected: 1 } });

  it('reads the sources own counts first, every status added up', () => {
    expect(brainGrowth([counts(3, 2), counts(1, 0)], { nodes: [], edges: [] })).toEqual({ verified: 4, total: 8 });
  });

  it('falls back to the facts on the map where no source counted any', () => {
    const map = { nodes: [{ id: 'a', kind: 'memory', label: 'a', status: 'settled' }, { id: 'b', kind: 'memory', label: 'b', status: 'recent' }, { id: 'c', kind: 'document', label: 'c' }], edges: [] } as MemoryMap;
    expect(brainGrowth([], map)).toEqual({ verified: 1, total: 2 });
  });
});

describe('the workspace lines under the heading', () => {
  it('says them in the Mac words, with this computer for this Mac', () => {
    for (const text of [WorkspaceFootLines.live, WorkspaceFootLines.unreachable, WorkspaceFootLines.refused, WorkspaceFootLines.saved]) expect(said(live, text), text).toBe(true);
    expect(said(pulled, WorkspaceFootLines.notJoined)).toBe(true);
    expect(onMac(WorkspaceFootLines.withheld(2))).toBe('2 more your workspace keeps from this Mac.');
    expect(said(pulled, WorkspaceFootLines.withheld(1))).toBe(true);
    const destination = read('MemnoxVoice/Presentation/App/MemoryDestination.swift');
    expect(destination).toContain(`"${WorkspaceFootLines.refresh}"`);
    expect(destination).toContain(`"${WorkspaceFootLines.openAccount}"`);
  });

  it('tells a computer not in a workspace how to join one, and nothing else', () => {
    expect(workspaceFoot({ source: 'saved', fallback: 'not-joined', withheld: 0 })).toEqual({ lines: [WorkspaceFootLines.notJoined], join: true });
  });

  it('says where the picture came from, when it was pulled and what was kept back', () => {
    expect(workspaceFoot({ source: 'live', withheld: 0 })).toEqual({ lines: ['Read live from your workspace'], join: false });
    expect(workspaceFoot({ source: 'saved', fallback: 'unreachable', withheld: 2, syncedAt: '2026-11-05T10:00:00Z' }).lines).toEqual([
      'Showing saved facts, the cloud could not be reached.',
      'Pulled from your workspace 2026-11-05',
      '2 more your workspace keeps from this computer.',
    ]);
  });
});

describe('the tour, as the Mac BrainTour', () => {
  it('runs the Mac loop over the Mac stretches', () => {
    expect(tour).toContain(`static let length = ${TOUR_LENGTH}.0`);
    for (const section of TOUR_SECTIONS) expect(tour).toContain(`TourSection(start: ${section.start}, part: .${section.part})`);
  });

  it('starts and ends the loop assembled, so it never jumps', () => {
    expect(poseAt(0)).toEqual(ASSEMBLED);
    const end = poseAt(TOUR_LENGTH - 0.001);
    expect(end.core + end.areas + end.rules + end.applications + end.apart).toBeCloseTo(0, 4);
    expect(end.zoom).toBeCloseTo(1, 4);
    expect(playhead(TOUR_LENGTH + 3)).toBeCloseTo(3, 4);
    expect(playhead(-1)).toBeCloseTo(TOUR_LENGTH - 1, 4);
  });

  it('opens each assembly alone in its own stretch', () => {
    const open: Record<string, keyof TourPose> = { core: 'core', areas: 'areas', rules: 'rules', applications: 'applications' };
    for (const [part, key] of Object.entries(open)) {
      const at = TOUR_SECTIONS.findIndex((section) => section.part === part);
      const middle = (TOUR_SECTIONS[at]!.start + TOUR_SECTIONS[at + 1]!.start) / 2;
      expect(sectionAt(middle).part).toBe(part);
      const pose = poseAt(middle);
      expect(pose[key], part).toBeCloseTo(1, 4);
      expect(pose.core + pose.areas + pose.rules + pose.applications - pose[key], part).toBeCloseTo(0, 4);
    }
  });

  it('opens everything in the teardown and turns once', () => {
    expect(sectionAt(19.5).part).toBe('teardown');
    expect(poseAt(19.5).apart).toBeCloseTo(1, 4);
    expect(poseAt(19.5).areas).toBeCloseTo(1, 4);
    expect(poseAt(23).turn).toBeCloseTo(2 * Math.PI, 4);
  });

  it('leaves every spot where it is while assembled', () => {
    for (const layer of ['skill', 'memory', 'rule', 'app'] as const) {
      expect(opened({ x: 0.3, y: -0.1 }, layer, { x: 0.2, y: -0.05 }, 0.4, ASSEMBLED)).toEqual({ x: 0.3, y: -0.1 });
    }
    expect(isAssembled(ASSEMBLED)).toBe(true);
  });

  it('moves an open assembly away from the middle', () => {
    const slid = opened({ x: 0.25, y: 0 }, 'memory', { x: 0.15, y: 0 }, 0.5, { ...ASSEMBLED, areas: 1 });
    expect(slid.x).toBeCloseTo(0.25 + TOUR_REACH.areaSlide, 6);
    const flown = opened({ x: 0.25, y: 0 }, 'app', undefined, 0.5, { ...ASSEMBLED, apart: 1 });
    expect(Math.hypot(flown.x, flown.y)).toBeGreaterThan(0.25 + TOUR_REACH.flightLeast - 1e-6);
  });

  it('eases a track between its keys', () => {
    const keys = [[0, 0], [2, 1]] as const;
    expect(sample(keys, -1)).toBe(0);
    expect(sample(keys, 1)).toBeCloseTo(0.5, 4);
    expect(sample(keys, 0.2)).toBeLessThan(0.1);
    expect(sample(keys, 3)).toBe(1);
  });

  it('holds, runs on and scrubs from one playhead, as BrainTourClock', () => {
    const started = { started: 1_000 };
    const held = toggleTour(started, 4_000);
    expect(held.held).toBeCloseTo(3, 6);
    expect(tourSeconds(held, 60_000)).toBeCloseTo(3, 6);
    const running = toggleTour(held, 10_000);
    expect(tourSeconds(running, 10_000)).toBeCloseTo(3, 6);
    expect(tourSeconds(scrubTour(running, 12, 20_000), 20_000)).toBeCloseTo(12, 6);
    expect(scrubTour(held, 8, 20_000).held).toBe(8);
  });

  it('names each stretch and counts what it opened on the deck, in the Mac words', () => {
    for (const part of ['assembled', 'core', 'areas', 'rules', 'applications', 'teardown', 'reassembly'] as const) expect(view).toContain(`"${tourName(part)}"`);
    expect(tourDetail('core', { skills: 1, areas: 0, rules: 0, applications: 0, marks: 0 })).toBe('1 FILE · SPREAD FROM THE MIDDLE');
    expect(tourDetail('teardown', { skills: 0, areas: 0, rules: 0, applications: 0, marks: 42 })).toBe('42 MARKS APART · TURNTABLE');
    expect(said(view, TourLines.overline)).toBe(true);
    expect(said(view, TourLines.rail)).toBe(true);
    expect(said(view, TourLines.leaveHelp)).toBe(true);
    expect(TourLines.count(3)).toBe('02 / 08');
    expect(sectionNumber(0)).toBe(1);
    expect(TourLines.clock(7.6)).toBe('00:07 / 00:25');
  });
});

describe('the brain measures', () => {
  it('draws at the Mac sizes, from the tokens', () => {
    expect(token('text-brain-headline')).toBe(swiftNumber(design, 'headline'));
    expect(token('text-brain-numeral')).toBe(swiftNumber(design, 'numeral'));
    expect(token('text-brain-overline')).toBe(swiftNumber(design, 'overline'));
    expect(token('text-brain-caption')).toBe(swiftNumber(design, 'caption'));
    expect(token('tracking-heading')).toBe(swiftNumber(design, 'headingTracking'));
    expect(token('tracking-title')).toBe(swiftNumber(design, 'titleTracking'));
    expect(token('spacing-brain-card')).toBe(swiftNumber(view, 'cardWidth'));
    expect(token('spacing-brain-heading')).toBe(swiftNumber(view, 'headingWidth'));
    expect(token('spacing-brain-seek')).toBe(swiftNumber(view, 'seekWidth'));
    expect(token('spacing-brain-seek-top')).toBe(swiftNumber(view, 'seekTop'));
    expect(token('spacing-brain-bar')).toBe(swiftNumber(view, 'barHeight'));
    const deck = view.slice(view.indexOf('private struct BrainTourDeck'));
    expect(token('spacing-brain-deck')).toBe(swiftNumber(deck, 'width'));
    expect(token('spacing-brain-play')).toBe(swiftNumber(deck, 'play'));
    expect(token('spacing-brain-rail')).toBe(swiftNumber(deck, 'rail'));
    expect(token('spacing-brain-knob')).toBe(swiftNumber(deck, 'knob'));
    expect(token('spacing-brain-tick')).toBe(swiftNumber(deck, 'tick'));
    expect(token('text-brain-mode')).toBe(swiftNumber(deck, 'mode'));
    expect(token('spacing-map-button')).toBe(swiftNumber(view.slice(view.indexOf('private struct MapButton')), 'side'));
    expect(token('spacing-map-box')).toBe(swiftNumber(view.slice(view.indexOf('private struct MapBox')), 'side'));
    const controls = view.slice(view.indexOf('private struct BrainViewControls'));
    expect(token('spacing-map-slider')).toBe(swiftNumber(controls, 'slider'));
    expect(token('spacing-map-divider')).toBe(swiftNumber(controls, 'divider'));
  });
});

describe('the legend inks', () => {
  it('dots each outer layer in the Mac ArmsInk', () => {
    const painter = read('MemnoxVoice/Presentation/App/MemoryArmsPainter.swift');
    expect(painter).toContain(`static let rules = Color(hex: 0x${LAYER_INK.rule.slice(1)})`);
    expect(painter).toContain(`static let applications = Color(hex: 0x${LAYER_INK.app.slice(1)})`);
    expect(design).toContain(`static let ink = Color(hex: 0x${LAYER_INK.skill.slice(1)})`);
  });
});
