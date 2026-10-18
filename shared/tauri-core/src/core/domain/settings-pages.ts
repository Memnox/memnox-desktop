/**
 * The pages of the Settings window, grouped as the Mac's `SettingsPage` groups them: the overview alone at
 * the top, then the person, this computer, the agents, the voice and help. Titles and the line under each
 * are the Mac's, with "this Mac" said as "this computer" since the window runs on Windows and Linux.
 */
export type SettingsPage =
  | 'overview'
  | 'account'
  | 'permissions'
  | 'connection'
  | 'phones'
  | 'appearance'
  | 'tools'
  | 'voice'
  | 'listening'
  | 'dictation'
  | 'help';

export interface SettingsPageInfo {
  readonly page: SettingsPage;
  readonly title: string;
  /** One line under the page's title saying what it is for, also the sidebar row's tooltip. */
  readonly subtitle: string;
}

const INFO: Record<SettingsPage, Omit<SettingsPageInfo, 'page'>> = {
  overview: { title: 'Overview', subtitle: 'What your agents are doing, and what is left to set up.' },
  account: { title: 'Account', subtitle: 'Your name, who you are in Memnox Cloud, and what that lets Memnox do on this computer.' },
  permissions: { title: 'Permissions', subtitle: 'What this computer lets Memnox hear, type and see.' },
  connection: { title: 'Connection', subtitle: 'The Memnox service your agents talk to, and the key your approvals are signed with.' },
  phones: { title: 'Phones', subtitle: 'Phones paired with this computer and what each may do.' },
  appearance: { title: 'Appearance', subtitle: 'Light, dark, or the same as this computer.' },
  tools: { title: 'Connected tools', subtitle: 'The agents on this computer and the apps Memnox can act in as you.' },
  voice: { title: 'Voice', subtitle: 'Who thinks for the voice, and the voice it answers in.' },
  listening: { title: 'Listening', subtitle: 'When Memnox listens and how it speaks up.' },
  dictation: { title: 'Dictation', subtitle: 'Speak instead of typing, in any app, written the way you would have typed it.' },
  help: { title: 'Help', subtitle: 'Rules, a quick test, and what happened for support.' },
};

export interface SettingsGroup {
  /** Absent for the overview, which stands alone above the groups. */
  readonly title: string | undefined;
  readonly pages: readonly SettingsPage[];
}

/** The sidebar's groups in order, as `SettingsPage.groups` lists them. */
export const SETTINGS_GROUPS: readonly SettingsGroup[] = [
  { title: undefined, pages: ['overview'] },
  { title: 'You', pages: ['account'] },
  { title: 'This computer', pages: ['permissions', 'connection', 'phones', 'appearance'] },
  { title: 'Agents and tools', pages: ['tools'] },
  { title: 'Voice', pages: ['voice', 'listening', 'dictation'] },
  { title: 'Support', pages: ['help'] },
];

/** Every page in sidebar order. */
export const SETTINGS_PAGES: readonly SettingsPage[] = SETTINGS_GROUPS.flatMap((group) => group.pages);

export function pageInfo(page: SettingsPage): SettingsPageInfo {
  return { page, ...INFO[page] };
}

/** A page named in a link, such as `?page=phones`, or undefined for anything else. */
export function pageNamed(name: string | null | undefined): SettingsPage | undefined {
  return SETTINGS_PAGES.find((page) => page === name);
}

/** Typing in the search field turns the groups into one flat list of the pages whose title or line match. */
export function matchingPages(query: string): readonly SettingsPage[] {
  const words = query.trim().toLowerCase();
  if (words === '') return SETTINGS_PAGES;
  return SETTINGS_PAGES.filter((page) => {
    const info = INFO[page];
    return info.title.toLowerCase().includes(words) || info.subtitle.toLowerCase().includes(words);
  });
}

/**
 * Where the window has been, for Back and Forward: a visit drops whatever was ahead, as a browser does,
 * and visiting the page already shown changes nothing.
 */
export class PageHistory {
  private visited: SettingsPage[];
  private at = 0;

  constructor(first: SettingsPage = 'overview') {
    this.visited = [first];
  }

  get current(): SettingsPage {
    return this.visited[this.at] ?? 'overview';
  }

  get canGoBack(): boolean {
    return this.at > 0;
  }

  get canGoForward(): boolean {
    return this.at < this.visited.length - 1;
  }

  visit(page: SettingsPage): void {
    if (page === this.current) return;
    this.visited = [...this.visited.slice(0, this.at + 1), page];
    this.at = this.visited.length - 1;
  }

  back(): void {
    if (this.canGoBack) this.at -= 1;
  }

  forward(): void {
    if (this.canGoForward) this.at += 1;
  }
}
