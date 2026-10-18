import { StrictMode, type ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import type { DaemonEvent, DaemonRequest, DaemonResponse, WorkDraft } from '@memnox/core/wire';
import { HeldCalls, ISLAND, ISLAND_WINDOW, ProposalCards, RequestIds, Setup, Signer, Talking, VoiceSettings, type ConfirmKey, type DaemonLink, type Speaker, type TalkState } from '../../core';
import { IslandNotices } from '../../core/application/island-notices';
import { DraftCard } from '../cards/DraftCard';
import { UnderIsland } from '../cards/UnderIsland';
import { Island } from '../Island';
import { NotchShape } from '../kit';
import { ToolPage } from './ToolPage';
import '../styles.css';

/**
 * The tray, tools and cards scenes inside the island, with no daemon: `pnpm dev`, then open
 * /previews/tools.html?scene=draft-github, or any scene below. The page alone lists them.
 */
const SCENES = ['draft-slack', 'draft-github', 'draft-gmail', 'draft-issue', 'rule-asked', 'pills', 'tool-page', 'tool-page-signin', 'mail-draft'] as const;
type Scene = (typeof SCENES)[number];

const asked = new URLSearchParams(window.location.search).get('scene') ?? '';
const scene: Scene | undefined = (SCENES as readonly string[]).includes(asked) ? (asked as Scene) : undefined;
const at = new Date().toISOString();

const link: DaemonLink = {
  async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
    if (request.method === 'waiting') yield { id: request.id, ok: true, waiting: [] };
    else if (request.method === 'subscribe') {
      yield { id: request.id, ok: true };
      await new Promise(() => undefined);
    } else yield { id: request.id, ok: true };
  },
};
const key: ConfirmKey = { publicPoint: async () => undefined, sign: async () => undefined };
const speaker: Speaker = { queue: () => undefined, drained: async () => undefined, stop: () => undefined };
const ids = new RequestIds();
const signer = new Signer(link, key, ids);
const never = () => () => undefined;
const calls = new HeldCalls(link, signer, ids, { timer: never });
const cards = new ProposalCards(link, signer, speaker, ids);
const talking = new Talking(link, speaker, signer, ids, { timer: never, cards });
const setup = new Setup(link, { found: async () => true, install: async () => true, wired: async () => true, run: async () => true }, ids, async () => undefined);
const voiceSettings = new VoiceSettings(link, ids);
void calls.watch();

const base: DaemonEvent = { kind: 'proposal', subject: 'prp_work', agent: 'agt_claude-code', agentName: 'Claude Code', summary: '', at };

const WORK: Record<string, WorkDraft> = {
  'draft-slack': {
    toolkit: 'slack',
    tool: 'SLACK_SEND_MESSAGE',
    kind: 'message',
    account: { handle: 'ana', check: 'matched' },
    to: ['#releases', '#desktop', '#design', '#qa', '#support'],
    body: 'The Windows and Linux island now matches the Mac: same buttons, colours, shapes and motion. Shots are in the thread.',
    fields: [{ name: 'unfurl_links', value: 'false' }],
  },
  'draft-github': {
    toolkit: 'github',
    tool: 'GITHUB_CREATE_REVIEW_COMMENT',
    kind: 'comment',
    account: { handle: 'moise10r', check: 'matched' },
    where: 'memnox/desktop#412',
    body: 'Looks good. The tray panel opens above the icon on Windows and below it on GNOME, so both read naturally.',
    fields: [{ name: 'commit_id', value: 'c4ac795' }],
  },
  'draft-gmail': {
    toolkit: 'gmail',
    tool: 'GMAIL_SEND_EMAIL',
    kind: 'email',
    account: { name: 'Ana Moreau', check: 'unverified' },
    to: ['lea@studio.fr'],
    subject: 'The desktop build for Thursday',
    body: 'Hi Léa,\n\nThe Windows build is ready for Thursday. I will send the installer link tonight.\n\nAna',
    fields: [],
  },
  'draft-issue': {
    toolkit: 'linear',
    tool: 'LINEAR_CREATE_ISSUE',
    kind: 'issue',
    account: { handle: 'ana', check: 'matched' },
    where: 'Desktop / Windows',
    subject: 'The tray panel does not close on a second click in Windows 10',
    body: 'Clicking the tray icon a second time should close the panel, as on the Mac.',
    fields: [
      { name: 'priority', value: '2' },
      { name: 'labels', value: 'bug, windows' },
    ],
  },
};

const work = scene === undefined ? undefined : WORK[scene];
if (work !== undefined) cards.show({ ...base, work });
if (scene === 'rule-asked')
  cards.show({
    ...base,
    subject: 'prp_rule',
    rule: {
      summary: 'ask before any push to main',
      effect: 'ask',
      action: 'git.push',
      branches: ['main'],
      reason: 'You said every push to main should wait for you.',
      scopes: [
        { id: 'machine', kind: 'machine', label: 'This computer', suggested: true },
        { id: 'repo', kind: 'repository', label: 'memnox-web', folder: '~/code/memnox-web' },
        { id: 'team', kind: 'team', label: 'The team' },
      ],
    },
  });

const talk = (heard: string): TalkState => ({ phase: 'thinking', heard, reply: '', failure: undefined });
const question = scene === 'rule-asked' ? 'From now on ask me before anything pushes to main' : scene === 'draft-slack' ? 'Tell the release channels the island is done' : undefined;

/** The island's notices with a sign in row, a signed in pill, a drive and a phone holding the voice. */
function noticesScene(): IslandNotices {
  const notices = new IslandNotices(never);
  const event = (fields: Partial<DaemonEvent>): DaemonEvent => ({ kind: 'notice', subject: 's', agent: 'agt_memnox', summary: '', at, ...fields });
  notices.handle(event({ drivenBy: { deviceId: 'd', name: 'Ana’s Pixel', until: new Date(Date.now() + 600_000).toISOString() } }));
  notices.handle(event({ notice: 'signed-in', signedIn: { toolkit: 'slack', account: { handle: 'ana', check: 'unverified' } } }));
  notices.handle(event({ kind: 'show', display: 'signin', signIn: [{ toolkit: 'gmail', url: 'https://x' }, { toolkit: 'linear', url: 'https://y', again: true }, { toolkit: 'figma', url: 'https://z' }] }));
  notices.handle(event({ voiceOn: { deviceId: 'd', name: 'Ana’s Pixel', holding: true } }));
  return notices;
}

/** The launcher's 512 by 230 island with its header, holding one page, as the tool page sits in it. */
function LauncherFrame({ title, children }: { title: string; children: ReactNode }) {
  const width = 512;
  const height = 230;
  return (
    <div className="relative mx-auto overflow-hidden font-sans text-white" data-theme="dark" style={{ width: ISLAND_WINDOW.width, height: ISLAND_WINDOW.height }}>
      <div className="absolute top-0" style={{ left: (ISLAND_WINDOW.width - width) / 2 - ISLAND.flare, width: width + 2 * ISLAND.flare, height }}>
        <NotchShape className="absolute inset-0" width={width + 2 * ISLAND.flare} height={height} flare={ISLAND.flare} bottomRadius={ISLAND.openBottomRadius} open />
        <div className="absolute top-0" style={{ left: ISLAND.flare, width, height }}>
          <div className="absolute inset-x-0 top-0 flex h-8 items-center pl-[46px] text-headline font-semibold">{title}</div>
          <div className="absolute inset-x-2.5 bottom-2.5 top-9">{children}</div>
        </div>
      </div>
    </div>
  );
}

function Scene() {
  switch (scene) {
    case 'pills':
      return (
        <div className="flex flex-col items-center gap-1.5 pt-10" data-theme="dark">
          <UnderIsland notices={noticesScene()} onSignIn={() => undefined} onNotMe={() => undefined} online={false} />
        </div>
      );
    case 'tool-page':
      return (
        <LauncherFrame title="Slack">
          <ToolPage toolkit="slack" connected onAsk={() => undefined} online={false} />
        </LauncherFrame>
      );
    case 'tool-page-signin':
      return (
        <LauncherFrame title="Figma">
          <ToolPage toolkit="figma" connected={false} onAsk={() => undefined} online={false} />
        </LauncherFrame>
      );
    case 'mail-draft':
      return (
        <div className="mx-auto mt-9 h-[384px] w-[520px]" data-theme="dark">
          <DraftCard
            className="h-full"
            draft={{ service: 'gmail', mode: 'reply', to: ['lea@studio.fr'], cc: ['tom@studio.fr'], subject: 'Re: The desktop build', body: 'Hi Léa,\n\nThursday works. The installer link follows tonight.\n\nAna', thread: 3 }}
            onAnswer={() => undefined}
          />
        </div>
      );
    case undefined:
      return (
        <ul style={{ margin: 12, padding: 12, background: '#111', color: '#fff', font: '12px system-ui', listStyle: 'none', borderRadius: 8 }}>
          {SCENES.map((each) => (
            <li key={each}>
              <a style={{ color: '#8cc8ff' }} href={`?scene=${each}`}>
                {each}
              </a>
            </li>
          ))}
        </ul>
      );
    default:
      return <Island calls={calls} talking={talking} cards={cards} setup={setup} voiceSettings={voiceSettings} preview={question === undefined ? {} : { talk: talk(question) }} />;
  }
}

const root = document.getElementById('root');
if (root === null) throw new Error('tools.html has no root');
createRoot(root).render(
  <StrictMode>
    <Scene />
  </StrictMode>,
);
