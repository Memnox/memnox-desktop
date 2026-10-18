import { invoke } from '@tauri-apps/api/core';
import { emitTo, listen } from '@tauri-apps/api/event';
import type { AgentNode, DisplayHost, TraceCard } from '@memnox/core/wire';
import type { FloatingCard } from '../../core/domain/floating-cards';
import type { MenuAction } from '../../core/domain/menu-panel';

/**
 * The windows beside the island, reached from the island's own window: the floating cards, the scan
 * screen and the tray panel. Rust makes each window and places it; the page in it draws, and they talk
 * by events named here, so both ends spell them once.
 */
export const WINDOW_EVENTS = {
  /** Asked for by the island's presenter, to any window. */
  cardAsked: 'floating-card',
  /** Sent to the cards window once it is up, so it never hears its own request twice. */
  card: 'floating-card-show',
  /** The daemon's dismiss, which every window that draws a card hears. */
  cardsDismiss: 'dismiss-cards',
  cardSession: 'card-session',
  scan: 'scan-agents',
  menuAction: 'menu-action',
  menuOpened: 'menu-opened',
  islandStatus: 'island-status',
} as const;

/** What a card asked for its session: the live window, or the session's own. */
export interface CardSessionAsk {
  readonly sessionId: string;
  readonly host: DisplayHost | undefined;
  readonly watch: boolean;
}

/** What the tray panel shows that only the island knows, sent each time the panel opens. */
export interface IslandStatus {
  readonly muted: boolean;
  readonly wakesByName: boolean;
  readonly talkKeys: readonly string[];
}

/** A card on screen in the top left, over whatever was there. */
export async function showCard(card: FloatingCard): Promise<void> {
  await invoke('cards_show');
  await emitTo('cards', WINDOW_EVENTS.card, card);
}

export function showSummary(card: Omit<Extract<FloatingCard, { kind: 'summary' }>, 'kind'>): Promise<void> {
  return showCard({ kind: 'summary', ...card });
}

export function showWalk(card: Omit<Extract<FloatingCard, { kind: 'walk' }>, 'kind'>): Promise<void> {
  return showCard({ kind: 'walk', ...card });
}

export function showTrace(trace: TraceCard, title: string): Promise<void> {
  return showCard({ kind: 'trace', title, trace });
}

/** Every floating card off the screen, faded rather than cut. */
export async function dismissCards(): Promise<void> {
  await emitTo('cards', WINDOW_EVENTS.cardsDismiss, null).catch(() => undefined);
}

/** Whenever the island's presenter asks for a floating card, the window is made and handed it. */
export function forwardCards(): () => void {
  const stop = listen<FloatingCard>(WINDOW_EVENTS.cardAsked, (event) => void showCard(event.payload).catch(() => undefined));
  return () => void stop.then((unlisten) => unlisten());
}

/** The whole screen scan of every agent here, with what each reaches. */
export async function showScan(agents: readonly AgentNode[], title: string): Promise<void> {
  await invoke('scan_show');
  await emitTo('scan', WINDOW_EVENTS.scan, { agents, title });
}

/** Whenever a card asks for its session; returns what stops listening. */
export function onCardSession(handle: (ask: CardSessionAsk) => void): () => void {
  const stop = listen<CardSessionAsk>(WINDOW_EVENTS.cardSession, (event) => handle(event.payload));
  return () => void stop.then((unlisten) => unlisten());
}

/** Whenever the tray panel or its menu asks the island for something. */
export function onMenuAction(handle: (action: MenuAction) => void): () => void {
  const stop = listen<MenuAction>(WINDOW_EVENTS.menuAction, (event) => handle(event.payload));
  return () => void stop.then((unlisten) => unlisten());
}

/** Answers the tray panel each time it opens with what only the island knows. */
export function answerMenuOpened(status: () => IslandStatus): () => void {
  const stop = listen(WINDOW_EVENTS.menuOpened, () => void emitTo('tray', WINDOW_EVENTS.islandStatus, status()).catch(() => undefined));
  return () => void stop.then((unlisten) => unlisten());
}

/** A line in the diary Rust keeps for Copy what happened: names and outcomes only, never words or arguments. */
export function noteInDiary(line: string): void {
  void invoke('diary_note', { line }).catch(() => undefined);
}
