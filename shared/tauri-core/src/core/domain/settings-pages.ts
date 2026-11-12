/**
 * The pages Settings and its moved pages answer to, as the Mac's `SettingsPage` names them. Titles and the line under
 * each are the Mac's, with "this Mac" said as "this computer" since the window runs on Windows and Linux.
 */
export type SettingsPage =
  | 'overview'
  | 'account'
  | 'permissions'
  | 'connection'
  | 'phones'
  | 'appearance'
  | 'tools'
  | 'apps'
  | 'voice'
  | 'listening'
  | 'dictation'
  | 'help';

export interface SettingsPageInfo {
  readonly page: SettingsPage;
  readonly title: string;
  /** One line under the page's title saying what it is for. */
  readonly subtitle: string;
}

const INFO: Record<SettingsPage, Omit<SettingsPageInfo, 'page'>> = {
  overview: { title: 'Overview', subtitle: 'What your agents are doing, and what is left to set up.' },
  account: { title: 'Account', subtitle: 'Your name, who you are in Memnox Cloud, and what that lets Memnox do on this computer.' },
  permissions: { title: 'Permissions', subtitle: 'What this computer lets Memnox hear, type and see.' },
  connection: { title: 'This computer', subtitle: 'The Memnox service on this computer, and the key that signs your yes.' },
  phones: { title: 'Phones', subtitle: 'Phones paired with this computer and what each may do.' },
  appearance: { title: 'Appearance', subtitle: 'Light, dark, or the same as this computer.' },
  tools: { title: 'Connected tools', subtitle: 'The agents on this computer and the apps Memnox can act in as you.' },
  apps: { title: 'Your apps', subtitle: 'Connect any tool you use as yourself, and see the ones this computer already reaches.' },
  voice: { title: 'Voice', subtitle: 'Who thinks for the voice, and the voice it answers in.' },
  listening: { title: 'Listening', subtitle: 'When Memnox listens and how it speaks up.' },
  dictation: { title: 'Dictation', subtitle: 'Speak instead of typing, in any app, written the way you would have typed it.' },
  help: { title: 'Help', subtitle: 'Rules, a quick test, setup again, and what happened for support.' },
};

/** Every page by name, which a link may name. */
const SETTINGS_PAGES: readonly SettingsPage[] = Object.keys(INFO).filter((page): page is SettingsPage => page in INFO);

export function pageInfo(page: SettingsPage): SettingsPageInfo {
  return { page, ...INFO[page] };
}

/** A page named in a link, such as `?page=phones`, or undefined for anything else. */
export function pageNamed(name: string | null | undefined): SettingsPage | undefined {
  return SETTINGS_PAGES.find((page) => page === name);
}
