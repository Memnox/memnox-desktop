import { describe, expect, it } from 'vitest';
import type { AgentNode, DaemonEvent } from '@memnox/core/wire';
import { Chiming } from '../src/core/application/chiming';
import { Diary } from '../src/core/application/diary';
import { IslandNotices } from '../src/core/application/island-notices';
import { toolChips, Tools } from '../src/core/application/tools';
import { answering, choiceForKey, joinedPicks, nextQuestion, questionCard, questionPosition } from '../src/core/domain/agent-question';
import { cueForAnswer, cueForEvent, cueForProposal, type Cue } from '../src/core/domain/chimes';
import { driveGrant, driveLabel, phoneVoice, phoneVoiceLabel } from '../src/core/domain/driving';
import { extensionBadge, openWords, pagePosition, pageSeconds, traceBar, traceSubtitle, traceTone } from '../src/core/domain/floating-cards';
import { inlineMarks, isOpenableLink, markdownBlocks } from '../src/core/domain/markdown';
import { chipTooltip, isMenuAction, listeningBadge, menuPanelPlace, menuRows, stripNote } from '../src/core/domain/menu-panel';
import { agentStatus, connectionLines, reachLine, ringPoint, scanCapabilities, scanCountLabel, scanRing, scanTotals } from '../src/core/domain/scan';
import { RequestIds } from '../src/core/application/request-ids';
import { ScriptedDaemon } from './doubles';

const at = '2026-10-18T10:00:00.000Z';
const event = (fields: Partial<DaemonEvent>): DaemonEvent => ({ kind: 'notice', subject: 's', agent: 'agt_codex', summary: '', at, ...fields });

describe('markdown blocks', () => {
  it('cuts headings, bullets, numbered items, code and lines, skipping blank lines', () => {
    const blocks = markdownBlocks('## Pushed\n\n- one\n* two\n3. three\n```\nconst a = 1;\n  b\n```\nplain line');
    expect(blocks).toEqual([
      { kind: 'heading', text: 'Pushed' },
      { kind: 'bullet', text: 'one' },
      { kind: 'bullet', text: 'two' },
      { kind: 'bullet', text: 'three' },
      { kind: 'code', text: 'const a = 1;\n  b' },
      { kind: 'text', text: 'plain line' },
    ]);
  });

  it('keeps a fence never closed as code, and a hash with no space as text', () => {
    expect(markdownBlocks('```\nleft open')).toEqual([{ kind: 'code', text: 'left open' }]);
    expect(markdownBlocks('#hashtag')).toEqual([{ kind: 'text', text: '#hashtag' }]);
    expect(markdownBlocks('3.5 seconds')).toEqual([{ kind: 'text', text: '3.5 seconds' }]);
  });

  it('marks code, bold, italics and links inside a line, code first', () => {
    expect(inlineMarks('Ran `pnpm **test**` and **passed** with *care*, see [the PR](https://x.dev/1).')).toEqual([
      { kind: 'plain', text: 'Ran ' },
      { kind: 'code', text: 'pnpm **test**' },
      { kind: 'plain', text: ' and ' },
      { kind: 'strong', text: 'passed' },
      { kind: 'plain', text: ' with ' },
      { kind: 'emphasis', text: 'care' },
      { kind: 'plain', text: ', see ' },
      { kind: 'link', text: 'the PR', href: 'https://x.dev/1' },
      { kind: 'plain', text: '.' },
    ]);
    expect(inlineMarks('snake_case_name stays')).toEqual([{ kind: 'plain', text: 'snake_case_name stays' }]);
  });

  it('opens only web links', () => {
    expect(isOpenableLink('https://memnox.com')).toBe(true);
    expect(isOpenableLink('file:///etc/passwd')).toBe(false);
  });
});

describe('chimes', () => {
  it('chimes for a held call and a settled one, never for a phone', () => {
    expect(cueForEvent(event({ kind: 'held' }), false)).toBe('held');
    expect(cueForEvent(event({ kind: 'settled' }), false)).toBe('settled');
    expect(cueForEvent(event({ kind: 'held' }), true)).toBeUndefined();
    expect(cueForEvent(event({ kind: 'notice' }), false)).toBeUndefined();
  });

  it('rings out an allow, pulls in a deny and says nothing for a cancelled prompt', () => {
    expect(cueForAnswer('once', 'answered')).toBe('allowed');
    expect(cueForAnswer('deny', 'answered')).toBe('declined');
    expect(cueForAnswer('once', 'answered-elsewhere')).toBe('settled');
    expect(cueForAnswer('once', 'failed')).toBe('failed');
    expect(cueForAnswer('once', 'cancelled')).toBeUndefined();
    expect(cueForProposal(true, 'answered')).toBe('done');
    expect(cueForProposal(false, 'answered')).toBe('declined');
  });

  it('plays through the port, and nothing once turned off or while a phone holds the voice', () => {
    const played: Cue[] = [];
    let phone = false;
    const chiming = new Chiming({ play: (cue) => played.push(cue) }, () => phone);
    chiming.heard(event({ kind: 'held' }));
    chiming.answered('deny', 'answered');
    phone = true;
    chiming.heard(event({ kind: 'held' }));
    chiming.enabled = false;
    chiming.answered('once', 'answered');
    expect(played).toEqual(['held', 'declined']);
  });
});

describe('driving', () => {
  const now = Date.parse(at);
  it('keeps a grant only while its time is ahead', () => {
    expect(driveGrant({ deviceId: 'd', name: 'Ana’s iPhone', until: '2026-10-18T10:05:00Z' }, now)).toEqual({ deviceId: 'd', name: 'Ana’s iPhone', until: now + 300_000 });
    expect(driveGrant({ deviceId: 'd', name: 'x', until: '2026-10-18T09:59:00Z' }, now)).toBeUndefined();
    expect(driveGrant({ deviceId: 'd', name: 'x' }, now)).toBeUndefined();
    expect(driveGrant({ deviceId: 'd', name: 'x', until: 'soon' }, now)).toBeUndefined();
  });

  it('names the phone, or says your phone', () => {
    expect(driveLabel({ name: 'Pixel' })).toBe('Driven from Pixel');
    expect(driveLabel({ name: '  ' })).toBe('Driven from your phone');
    expect(phoneVoiceLabel({ name: '' })).toBe('Talking on your phone');
    expect(phoneVoice({ deviceId: 'd', name: 'P', holding: false })).toBeUndefined();
  });
});

describe('agent question', () => {
  const asked = event({
    notice: 'question',
    agentName: 'Claude Code',
    questions: [
      { question: 'Which database?', options: [{ label: 'Postgres' }, { label: 'SQLite' }], multiSelect: false },
      { question: 'Which checks?', options: [{ label: 'Lint' }, { label: 'Types' }, { label: 'Tests' }], multiSelect: true },
    ],
    answers: {},
  });

  it('is a card only for a question with choices', () => {
    expect(questionCard(event({ notice: 'finished' }))).toBeUndefined();
    expect(questionCard(asked)?.who).toBe('Claude Code');
  });

  it('asks the first unanswered question, numbered from one, and moves on', () => {
    const card = questionCard(asked);
    if (card === undefined) throw new Error('no card');
    expect(nextQuestion(card)?.number).toBe(1);
    expect(questionPosition(card)).toBe('1 of 2');
    const moved = answering(card, 1, 'Postgres');
    expect(nextQuestion(moved)?.item.question).toBe('Which checks?');
    expect(answering(moved, 9, 'x')).toBe(moved);
  });

  it('joins several picks in the order the agent listed them, and maps number keys', () => {
    const card = questionCard(asked);
    const item = card?.questions[1];
    if (item === undefined) throw new Error('no item');
    expect(joinedPicks(new Set(['Tests', 'Lint']), item)).toBe('Lint, Tests');
    expect(choiceForKey(item, '2')?.label).toBe('Types');
    expect(choiceForKey(item, '7')).toBeUndefined();
    expect(choiceForKey(item, 'a')).toBeUndefined();
  });
});

describe('menu panel', () => {
  it('lists the rows in the Mac order, mute keeping the panel open', () => {
    const rows = menuRows(false, ['Ctrl', 'Alt', 'Space']);
    expect(rows.map((row) => row.title)).toEqual(['Talk to Memnox', 'Say a rule', 'Copy what happened', 'Mute voice', 'Settings', 'Quit Memnox']);
    expect(rows[3]?.staysOpen).toBe(true);
    expect(rows[4]?.dividerAbove).toBe(true);
    expect(rows[5]?.quiet).toBe(true);
    expect(menuRows(true, [])[3]?.title).toBe('Unmute voice');
  });

  it('says how to start a talk in the badge', () => {
    expect(listeningBadge(false, ['\u2325', 'Space']).text).toBe('\u2325 Space to talk');
    expect(listeningBadge(false, ['Ctrl', 'Alt', 'Space'])).toMatchObject({ text: 'Ctrl Alt Space', tooltip: 'Press Ctrl Alt Space to talk' });
    expect(listeningBadge(true, []).lit).toBe(true);
  });

  it('notes the strip when it has no chips', () => {
    expect(stripNote(true, undefined, [])).toBe('Reading your tools');
    expect(stripNote(false, 'Memnox is not running', [])).toBe('Memnox is not running');
    expect(stripNote(false, undefined, [])).toBe('No tools connected yet');
    expect(stripNote(false, 'x', [{ id: 'a', kind: 'app', key: 'slack', name: 'Slack', ready: true }])).toBeUndefined();
    expect(chipTooltip({ id: 'a', kind: 'app', key: 'slack', name: 'Slack', ready: false })).toBe('Slack needs you');
  });

  it('opens above a tray at the bottom and below one at the top, clamped inside the screen', () => {
    const screen = { x: 0, y: 0, width: 1920, height: 1040 };
    expect(menuPanelPlace({ x: 1800, y: 1050, width: 24, height: 24 }, { ...screen, height: 1080 }, { width: 300, height: 400 })).toEqual({ x: 1612, y: 644 });
    expect(menuPanelPlace({ x: 900, y: 4, width: 24, height: 24 }, screen, { width: 300, height: 400 })).toEqual({ x: 762, y: 34 });
    expect(menuPanelPlace({ x: 2, y: 4, width: 24, height: 24 }, screen, { width: 300, height: 400 }).x).toBe(8);
  });

  it('knows its actions', () => {
    expect(isMenuAction('talk')).toBe(true);
    expect(isMenuAction('format-disk')).toBe(false);
  });
});

describe('floating cards', () => {
  it('turns a page as long as its note takes to say, four seconds at least', () => {
    expect(pageSeconds({ note: 'short' })).toBe(4);
    expect(pageSeconds({ note: 'x'.repeat(140) })).toBe(10);
    expect(pagePosition(1, 5)).toBe('2 of 5');
  });

  it('places a trace bar on its clock, keeping even an instant step visible', () => {
    expect(traceBar({ name: 'a', depth: 6, offsetMs: 500, durationMs: 0, status: 'ok' }, 1000, 170)).toEqual({ offset: 85, width: 3, indent: 48 });
    expect(traceTone({ status: 'error', depth: 1 })).toBe('destructive');
    expect(traceTone({ status: 'refused', depth: 0 })).toBe('warm');
    expect(traceTone({ status: 'ok', depth: 0 })).toBe('primary');
    expect(traceTone({ status: 'ok', depth: 2 })).toBe('success');
    expect(traceSubtitle(1)).toBe('1 step');
  });

  it('badges a file by its extension', () => {
    expect(extensionBadge('src/ui/Island.tsx')).toBe('TSX');
    expect(extensionBadge('Makefile')).toBe('TXT');
    expect(extensionBadge('a/b.markdown')).toBe('MAR');
    expect(openWords({ app: 'Cursor' }, 'Open session')).toBe('Open in Cursor');
    expect(openWords(undefined, 'Open session')).toBe('Open session');
  });
});

describe('scan', () => {
  const agents: AgentNode[] = [
    { id: '1', kind: 'claude-code', name: 'Claude Code', servers: 2, reaches: ['shell', 'filesystem', 'git', 'network'], working: 1, open: 0, mcp: [{ name: 'github', tools: 30, changing: 12 }, { name: 'linear', tools: 10, changing: 4 }], clis: ['gh', 'aws', 'gcloud', 'fly', 'vercel'] },
    { id: '2', kind: 'cursor', name: 'Cursor', servers: 0, reaches: [], working: 0, open: 2 },
  ];

  it('describes what each agent reaches in counted facts', () => {
    expect(reachLine(agents[0] as AgentNode)).toBe('2 MCP servers · shell · files · git');
    expect(reachLine(agents[1] as AgentNode)).toBe('nothing beyond its own app');
    expect(connectionLines(agents[0] as AgentNode)).toEqual(['mcp  github 30 · linear 10', 'cli  gh · aws · gcloud · fly +1']);
    expect(agentStatus(agents[1] as AgentNode)).toEqual({ text: '2 waiting on you', tone: 'amber' });
  });

  it('totals the screen and lays the ring from the top', () => {
    expect(scanTotals(agents)).toEqual({ agents: 2, tools: 40, changing: 16, working: 1 });
    expect(scanRing({ width: 1000, height: 800 }).width).toBe(340);
    expect(scanRing({ width: 4000, height: 2000 })).toEqual({ width: 560, height: 320 });
    const top = ringPoint(0, 4, { x: 0, y: 0 }, { width: 100, height: 50 });
    expect(top.x).toBeCloseTo(0);
    expect(top.y).toBeCloseTo(-50);
    expect(scanCountLabel(1)).toBe('agent on this computer');
  });

  it('adds up the real capabilities the runtime credits each agent, and says counting rather than zero', () => {
    const counted = [
      { ...agents[0], capabilities: { total: 7, areas: [] } },
      { ...agents[1], capabilities: { total: 0, areas: [] } },
    ] as AgentNode[];
    expect(scanCapabilities(counted)).toBe(7);
    const counting = [{ ...agents[0], capabilities: { areas: [] } }, agents[1]] as AgentNode[];
    expect(scanCapabilities(counting)).toBeUndefined();
    // A runtime that sends no shares keeps the older per server figure.
    expect(scanCapabilities(agents)).toBe(16);
  });
});

describe('tools', () => {
  it('reads agents and apps together, the voice first, and makes chips of both', async () => {
    const daemon = new ScriptedDaemon({
      'voice-agents': (request) => [
        {
          id: request.id,
          ok: true,
          voiceAgents: [
            { kind: 'codex', label: 'Codex', installed: true, sealed: true, works: false, chosen: false, install: '' },
            { kind: 'claude-code', label: 'Claude Code', installed: true, sealed: true, works: true, chosen: true, install: '' },
            { kind: 'cursor', label: 'Cursor', installed: false, sealed: true, chosen: false, install: '' },
          ],
        },
      ],
      'connections-list': (request) => [{ id: request.id, ok: true, connections: [{ toolkit: 'slack', connected: true }, { toolkit: 'gmail', connected: false }] }],
    });
    const tools = new Tools(daemon, new RequestIds());
    expect(tools.state.reading).toBe(true);
    await tools.refresh();
    expect(tools.state.agents.map((each) => each.kind)).toEqual(['claude-code', 'codex']);
    expect(tools.connectedCount).toBe(1);
    expect(tools.chips.map((chip) => [chip.name, chip.ready])).toEqual([
      ['Claude Code', true],
      ['Codex', false],
      ['Slack', true],
      ['Gmail', false],
    ]);
  });

  it('says the daemon is not running when nothing answers', async () => {
    const tools = new Tools({ stream: async function* () {} }, new RequestIds());
    await tools.refresh();
    expect(tools.state.connectionsNote).toBe('Memnox is not running');
    expect(toolChips(tools.state)).toEqual([]);
  });
});

describe('island notices', () => {
  function clock() {
    let now = Date.parse(at);
    const pending: { at: number; fire: () => void }[] = [];
    return {
      now: () => now,
      timer: (ms: number, fire: () => void) => {
        const entry = { at: now + ms, fire };
        pending.push(entry);
        return () => pending.splice(pending.indexOf(entry), 1);
      },
      pass(ms: number) {
        now += ms;
        for (const entry of [...pending].filter((each) => each.at <= now)) {
          pending.splice(pending.indexOf(entry), 1);
          entry.fire();
        }
      },
    };
  }

  it('hangs the sign in row and swaps a tool for its pill once signed in', () => {
    const time = clock();
    const notices = new IslandNotices(time.timer, time.now);
    notices.handle(event({ kind: 'show', display: 'signin', signIn: [{ toolkit: 'slack', url: 'https://x' }, { toolkit: 'gmail', url: 'https://y', again: true }] }));
    expect(notices.state.signIns.map((each) => each.toolkit)).toEqual(['slack', 'gmail']);
    notices.handle(event({ notice: 'signed-in', signedIn: { toolkit: 'slack', account: { handle: 'ana', check: 'matched' } } }));
    expect(notices.state.signIns.map((each) => each.toolkit)).toEqual(['gmail']);
    expect(notices.state.signedIn).toMatchObject({ toolkit: 'slack', who: 'ana', unverified: false });
    time.pass(3_000);
    expect(notices.state.signedIn).toBeUndefined();
  });

  it('keeps an unverified pill longer, and ignores a sign in that never finished', () => {
    const time = clock();
    const notices = new IslandNotices(time.timer, time.now);
    notices.handle(event({ notice: 'signed-in', signedIn: { toolkit: 'gmail' } }));
    expect(notices.state.signedIn).toBeUndefined();
    notices.handle(event({ notice: 'signed-in', signedIn: { toolkit: 'gmail', account: { name: 'Ana', check: 'unverified' } } }));
    time.pass(3_000);
    expect(notices.state.signedIn?.unverified).toBe(true);
    time.pass(5_000);
    expect(notices.state.signedIn).toBeUndefined();
  });

  it('shows a drive for the length of its grant and a phone holding the voice', () => {
    const time = clock();
    const notices = new IslandNotices(time.timer, time.now);
    notices.handle(event({ drivenBy: { deviceId: 'd', name: 'Pixel', until: '2026-10-18T10:01:00Z' } }));
    expect(notices.state.driving?.name).toBe('Pixel');
    time.pass(60_000);
    expect(notices.state.driving).toBeUndefined();
    notices.handle(event({ voiceOn: { deviceId: 'd', name: 'Pixel', holding: true } }));
    expect(notices.state.phoneVoice?.name).toBe('Pixel');
    notices.handle(event({ voiceOn: { deviceId: 'd', name: 'Pixel', holding: false } }));
    expect(notices.state.phoneVoice).toBeUndefined();
  });
});

describe('diary', () => {
  it('keeps the newest lines, stamped, under a heading', () => {
    const diary = new Diary(() => Date.parse(at), 2);
    diary.note('one');
    diary.note('two');
    diary.note('three');
    expect(diary.count).toBe(2);
    expect(diary.text('Windows')).toBe(`Memnox: what happened, Windows\n${at} two\n${at} three`);
  });
});
