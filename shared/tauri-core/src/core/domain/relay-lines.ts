/** The relay and team cards' words under Phones, as the Mac says them. */

export const RelayLines = {
  connectServer: 'Connect to a server',
  connectServerDetail: 'Optional. Talk to Memnox on a Linux server through the relay. Run memnox pair there and paste the link it prints.',
  connect: 'Connect',
  talking: 'Talking to it',
  talkTo: 'Talk to it',
  forget: 'Forget',
  cancel: 'Cancel',
  signOut: 'Sign out',
  tryAgain: 'Try again',
  signIn: 'Sign in',
  teamCalls: "Your team's calls",
  signedInAs: (name: string, keyTitle: string) => `Signed in as ${name}. Calls your workspace routes to you show on the island, and every yes asks for ${keyTitle}.`,
  answerCalls: (keyTitle: string) => `Answer the calls your workspace routes to you from the island, each yes signed with ${keyTitle}.`,
} as const;
