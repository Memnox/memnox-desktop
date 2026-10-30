import type { LanStatus } from '@memnox/core/wire';

/** What the local network does, said before the switch so nobody turns on what they cannot name. */
export const LAN_WHAT = 'Lets your paired phones reach this computer straight over the network you share, rather than through the relay. The conversation is encrypted end to end the same way either way.';

/** Where it listens and that it starts off, which the card says whether it is on or not. */
export const LAN_BOUNDS = 'It stays off until you turn it on, and it only ever listens on a private address, such as your home or office network, never a public one.';

/** Said on the Phones page while it is on, since pairing then needs nothing beyond the network. */
export const LAN_PAIRS_WITHOUT_ACCOUNT = 'The local network is on, so a phone on the same network can pair with this computer with no Memnox account.';

/** The switch's caption: turning off narrows who reaches this computer, so only turning on asks for the key. */
export function lanSwitchCaption(on: boolean, keyTitle: string): string {
  return on ? 'Turn off to stop it at once' : `${keyTitle} to turn on`;
}

/** Where it stands, in a sentence: off, on with nothing listening, or listening and where. */
export function lanStatusLine(lan: Pick<LanStatus, 'on' | 'listening' | 'addresses' | 'port' | 'advertised'>): string {
  if (!lan.on) return 'Off. Your phones reach this computer through the relay.';
  if (!lan.listening || lan.addresses.length === 0) return 'On, but this computer has no private network address right now, so nothing is listening.';
  const where = lan.port === undefined ? lan.addresses.join(', ') : lan.addresses.map((address) => `${address}:${lan.port}`).join(', ');
  const announced = lan.advertised ? ', announced to phones nearby under a name that says nothing about this computer' : '';
  return `Listening on ${where}${announced}.`;
}

/** Which paired phones are connected over it now, by name. */
export function lanPhonesLine(lan: Pick<LanStatus, 'on' | 'reachable'>): string {
  if (lan.reachable.length === 0) return lan.on ? 'No phone is connected over it now.' : 'No phone is connected over it.';
  const names = lan.reachable.map((phone) => phone.name);
  const said = names.length === 1 ? (names[0] ?? '') : `${names.slice(0, -1).join(', ')} and ${names.at(-1) ?? ''}`;
  return `${said} ${names.length === 1 ? 'is' : 'are'} connected over it now.`;
}

/** Said once turning it on was proposed: nothing listens until the person signs it. */
export function lanWaitsLine(keyTitle: string): string {
  return `Nothing is listening yet. Turning it on waits for your signature with ${keyTitle} on the island.`;
}
