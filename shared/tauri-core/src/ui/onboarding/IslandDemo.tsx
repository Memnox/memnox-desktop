import { useEffect, useMemo, useState } from 'react';
import type { DaemonEvent, DaemonRequest, DaemonResponse } from '@memnox/core/wire';
import { AgentQuestions, HeldCalls, ProposalCards, RequestIds, Sessions, Setup, Signer, Talking, VoiceSettings, type DaemonLink, type Runtime, type Speaker } from '../../core';
import type { WelcomeRow } from '../../core/domain/onboarding';
import { Island, type IslandParts, type IslandPreview } from '../Island';
import { PREVIEW_CARDS, PREVIEW_VIEWS } from '../sessions/preview-data';

/**
 * The real island beside the first run's steps, played through what it does with made up sessions and no
 * daemon, as the Mac's `IslandDemo`: every agent at a glance, a call answered, a rule said, a reply in the
 * person's own tools and a catch up. Its buttons answer nothing, since nothing real waits behind them.
 */

/** How long each part plays before the next, as the Mac's dwell between its chapters. */
export const DEMO_PART_MS = 6_500;
/** The island window's own size, drawn smaller to fit beside the steps. */
const WINDOW = { width: 740, height: 672 } as const;
const SCALE = 0.42;
/** How much of the window shows under the screen's top edge, which is all an open island takes. */
const SHOWN_HEIGHT = 300;

const at = new Date().toISOString();
const held: DaemonEvent = {
  kind: 'held',
  subject: 'hld_demo',
  agent: 'agt_codex',
  agentName: 'Codex',
  summary: 'Codex wants to push to main',
  what: 'git push origin feature/invoices:main',
  why: 'wants to push to main',
  place: 'shop',
  at,
};

/** A world of its own for one part, so a part that plays again starts as it did the first time. */
function world(part: WelcomeRow['id']): { parts: IslandParts; preview: IslandPreview } {
  const link: DaemonLink = {
    async *stream(request: DaemonRequest): AsyncIterable<DaemonResponse> {
      if (request.method === 'waiting') yield { id: request.id, ok: true, waiting: part === 'answer' ? [held] : [] };
      else if (request.method === 'sessions-list') yield { id: request.id, ok: true, sessions: PREVIEW_CARDS };
      else if (request.method === 'session-view') yield { id: request.id, ok: true, session: PREVIEW_VIEWS[request.sessionId ?? ''] };
      else if (request.method === 'subscribe') {
        yield { id: request.id, ok: true };
        await new Promise(() => undefined);
      } else yield { id: request.id, ok: true };
    },
  };
  const speaker: Speaker = { queue: () => undefined, drained: async () => undefined, stop: () => undefined };
  const ids = new RequestIds();
  const signer = new Signer(link, { publicPoint: async () => undefined, sign: async () => undefined }, ids);
  const still = () => () => undefined;
  const calls = new HeldCalls(link, signer, ids, { timer: still });
  const cards = new ProposalCards(link, signer, speaker, ids);
  const talking = new Talking(link, speaker, signer, ids, { timer: still, cards });
  const runtime: Runtime = { found: async () => true, install: async () => true, wired: async () => true, run: async () => true };
  const sessions = new Sessions(link, ids, still);
  void calls.watch();
  void sessions.refresh();
  if (part === 'glance') sessions.opened(true);
  if (part === 'rule')
    cards.show({
      ...held,
      kind: 'proposal',
      subject: 'prp_demo_rule',
      rule: {
        summary: 'ask before any push to main',
        effect: 'ask',
        action: 'git.push',
        branches: ['main'],
        reason: 'You said never to push to main without asking you first.',
        scopes: [
          { id: 'machine', kind: 'machine', label: 'This computer' },
          { id: 'repo', kind: 'repository', label: 'shop', folder: '~/code/shop', suggested: true },
        ],
      },
    } as DaemonEvent);
  if (part === 'tools')
    cards.show({
      ...held,
      kind: 'proposal',
      subject: 'prp_demo_work',
      work: {
        toolkit: 'gmail',
        tool: 'GMAIL_SEND_EMAIL',
        kind: 'email',
        account: { name: 'You', check: 'matched' },
        to: ['sam@example.com'],
        subject: 'The new site',
        body: 'Hi Sam, the new site is live. Here is the link.',
        fields: [],
      },
    } as DaemonEvent);
  const preview: IslandPreview =
    part === 'glance'
      ? { opened: true }
      : part === 'catch-up'
        ? {
            talk: {
              phase: 'speaking',
              heard: 'What did my agents do while I was out?',
              reply: 'Codex finished the invoice change in shop and every test passes. Claude Code is still on the side panel and needs nothing from you.',
              failure: undefined,
            },
          }
        : {};
  return {
    parts: { calls, talking, cards, setup: new Setup(link, runtime, ids, async () => undefined), voiceSettings: new VoiceSettings(link, ids), sessions, questions: new AgentQuestions(link, ids, still), preview },
    preview,
  };
}

/** The demo's order, the rows of the welcome step. */
export const DEMO_PARTS: readonly WelcomeRow['id'][] = ['glance', 'answer', 'rule', 'tools', 'catch-up'];

/** Plays the parts round and round from the one given, telling the step which part plays so it lights that row. */
export function useDemoTour(start: WelcomeRow['id'] | undefined): [WelcomeRow['id'], (part: WelcomeRow['id']) => void] {
  const [part, setPart] = useState<WelcomeRow['id']>(start ?? 'glance');
  useEffect(() => {
    const next = setTimeout(() => setPart(DEMO_PARTS[(DEMO_PARTS.indexOf(part) + 1) % DEMO_PARTS.length] ?? 'glance'), DEMO_PART_MS);
    return () => clearTimeout(next);
  }, [part]);
  return [part, setPart];
}

/** The screen beside the steps with the real island hanging from its top, playing `part`. */
export function IslandDemo({ part }: { part: WelcomeRow['id'] }) {
  const shown = useMemo(() => world(part), [part]);
  return (
    <div className="pointer-events-none flex min-w-0 flex-1 py-9" aria-hidden>
      <div className="relative flex flex-1 items-end justify-center overflow-hidden rounded-3xl border border-ink-rim p-6" style={{ background: 'linear-gradient(#86B3C9, #4F7BB3)' }}>
        <div className="relative aspect-[828/634] w-full max-w-[520px] rounded-t-[22px] bg-[#0C0C0D] px-[1.7%] pt-[1.7%] shadow-[0_14px_24px_rgba(0,0,0,.35)] [mask-image:linear-gradient(black_82%,transparent)]">
          <div className="relative h-full overflow-hidden rounded-t-[14px]" style={{ background: 'linear-gradient(160deg, #1E86EE, #0a3d7a)' }}>
            <div
              key={part}
              className="absolute top-0 left-1/2 animate-[fade-in_300ms_ease-out]"
              style={{ width: WINDOW.width, height: SHOWN_HEIGHT, marginLeft: -WINDOW.width / 2, transform: `scale(${SCALE})`, transformOrigin: 'top center' }}
            >
              <div className="relative" style={{ width: WINDOW.width, height: WINDOW.height }}>
                <Island {...shown.parts} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
