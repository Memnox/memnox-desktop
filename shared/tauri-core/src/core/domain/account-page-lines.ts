/** The Account page's words, as the Mac's AccountPage says them. */

export const AccountPageLines = {
  you: 'You',
  cloud: 'Memnox Cloud',
  turnsOn: 'What signing in turns on',
  appsMove: 'Apps you already connected on this computer move into your account with you.',
  rulesReach: 'Your rules, workspace memory and phone pairing reach this computer.',
  yourName: 'Your name',
  nameDetail: 'What Memnox calls you.',
  signIn: 'Sign in',
  cancel: 'Cancel',
  signOut: 'Sign out',
  finish: 'Finish',
  update: 'Update',
  callsRouted: (keyTitle: string) => `Calls your workspace routes to you show in the island, and every yes asks for ${keyTitle}.`,
} as const;
