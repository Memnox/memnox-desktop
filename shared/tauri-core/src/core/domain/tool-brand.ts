/**
 * How each connected tool looks and what it says, ported from the Mac's `ToolBrand`, `ToolkitName`,
 * `ToolAsks` and the work card's own words, so every screen names and colours a tool the same way.
 */

/** A tool's look: its colour, and the word on its own send button. */
export interface ToolLook {
  readonly colour: string;
  readonly send: string;
}

const LOOKS: Record<string, ToolLook> = {
  slack: { colour: '#4A154B', send: 'Send' },
  github: { colour: '#238636', send: 'Comment' },
  linear: { colour: '#5E6AD2', send: 'Comment' },
  gmail: { colour: '#EA4335', send: 'Send' },
  googledocs: { colour: '#4285F4', send: 'Save' },
  notion: { colour: '#2F3437', send: 'Save' },
};

/** A tool with no look of its own is drawn in the Memnox blue, so it is never mistaken for one that has. */
export const FALLBACK_LOOK: ToolLook = { colour: '#1E86EE', send: 'Send' };

/** The tools that ship their own mark, which the rest draw as an initial until Composio sends a logo. */
export const BRANDED_TOOLS: readonly string[] = Object.keys(LOOKS);

export function toolLook(toolkit: string): ToolLook {
  return LOOKS[toolkit] ?? FALLBACK_LOOK;
}

export function hasOwnMark(toolkit: string): boolean {
  return LOOKS[toolkit] !== undefined;
}

const NAMES: Record<string, string> = {
  github: 'GitHub',
  gmail: 'Gmail',
  googledocs: 'Google Docs',
  linear: 'Linear',
  notion: 'Notion',
  slack: 'Slack',
};

/** How the person reads a tool's name, which its slug says badly: capitalised where it is not known. */
export function toolkitName(toolkit: string): string {
  return NAMES[toolkit] ?? toolkit.charAt(0).toUpperCase() + toolkit.slice(1);
}

const ASKS: Record<string, readonly string[]> = {
  slack: ['Catch me up on Slack since this morning', 'What did people ask me on Slack today?', 'Post a status update in Slack about what I shipped today'],
  linear: ['What is on my plate in Linear this week?', 'Which of my Linear issues are blocked?', 'File a Linear issue for what I am working on'],
  gmail: ['What in my inbox needs a reply?', 'Summarise my unread email', 'Draft a reply to my latest email'],
  github: ['Which pull requests are waiting on my review?', 'What failed in CI today?', 'Summarise what merged this week'],
  notion: ['What changed in Notion this week?', 'Find my latest notes in Notion', "Write today's progress into Notion"],
  googledocs: ['Which Google Docs were shared with me this week?', 'Summarise the doc I opened last', 'Draft a doc from what I worked on today'],
};

/**
 * What a person can ask Memnox about a tool, offered as taps on its page. Each goes whole to ask as if
 * it were said, so the daemon decides what it means and nothing here acts on it.
 */
export function toolAsks(toolkit: string): readonly string[] {
  const known = ASKS[toolkit];
  if (known !== undefined) return known;
  const name = toolkitName(toolkit);
  return [`What is new in ${name}?`, `What needs me in ${name}?`, `Summarise my week in ${name}`];
}

/** The line under a tool page's asks; the talk key is named the way this computer spells it. */
export function toolPageHint(toolkit: string, connected: boolean, talkKey: string): string {
  return connected ? `Or press ${talkKey} and ask anything about ${toolkitName(toolkit)}.` : 'Ask anything and Memnox opens the sign in first.';
}

/** The kinds of draft the daemon names, each laid out the way its own tool lays it out. */
export type WorkLayout = 'message' | 'comment' | 'email' | 'generic';

export function workLayout(kind: string): WorkLayout {
  switch (kind) {
    case 'message':
      return 'message';
    case 'comment':
      return 'comment';
    case 'email':
      return 'email';
    default:
      return 'generic';
  }
}

/** The card's title: "Review comment on GitHub", "Message on Slack", "Action on Figma". */
export function workTitle(kind: string, toolkit: string): string {
  const word = ((): string => {
    switch (kind) {
      case 'message':
        return 'Message';
      case 'comment':
        return toolkit === 'github' ? 'Review comment' : 'Comment';
      case 'email':
        return 'Email';
      case 'issue':
        return 'Issue';
      default:
        return 'Action';
    }
  })();
  return `${word} on ${toolkitName(toolkit)}`;
}

/** What the work card's footer says now: the key prompt up, nothing left to send, their own words, or the promise. */
export function workFootnote(state: { sending: boolean; empty: boolean; changed: boolean }, keyName: string): string {
  if (state.sending) return `Waiting for ${keyName}`;
  if (state.empty) return 'Write something to send.';
  if (state.changed) return 'Your words go out as you wrote them.';
  return 'Nothing goes out until you send it.';
}

/** How many recipients fit on one row; the rest are counted and named on hover. */
export const SHOWN_PEOPLE = 3;

/** The recipients a card names, and how many more it only counts. */
export function shownPeople(people: readonly string[]): { shown: readonly string[]; more: number } {
  return { shown: people.slice(0, SHOWN_PEOPLE), more: Math.max(0, people.length - SHOWN_PEOPLE) };
}

/** The avatar's letter: the first of the name the card shows, or of "You". */
export function avatarLetter(shown: string | undefined): string {
  return (shown ?? 'You').charAt(0).toUpperCase();
}

/** The signed in pill's words: "Slack · ana" or "Signed in to Slack". */
export function signedInWords(toolkit: string, who: string | undefined): string {
  const tool = toolkitName(toolkit);
  return who === undefined ? `Signed in to ${tool}` : `${tool} · ${who}`;
}

/** The sign in row's lead: "Sign in" when one of them signs in again, else "Sign in to use". */
export function signInLead(again: readonly boolean[]): string {
  return again.some(Boolean) ? 'Sign in' : 'Sign in to use';
}

/** A sign in row mark's tooltip. */
export function signInLabel(toolkit: string, again: boolean): string {
  const name = toolkitName(toolkit);
  return again ? `Sign in to ${name} again, with your own account` : `Sign in to ${name}`;
}

/** How long the signed in pill stays: longer when it asks "Not me", so there is time to say it. */
export const SIGNED_IN_FOR_MS = { verified: 3_000, unverified: 8_000 } as const;
