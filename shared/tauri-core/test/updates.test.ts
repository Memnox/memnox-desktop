import { describe, expect, it } from 'vitest';
import type { ReleaseFeed } from '../src/core/application/ports/release-feed';
import { Updates, type UpdateFacts } from '../src/core/application/updates';
import { isNewer, newestAppRelease, newestRuntimeVersion, offered, UpdateLines } from '../src/core/domain/updates';

/** A newer Memnox is offered once, put off one version at a time, and never decided for the person. */

const release = (tag: string, assets: string[], over: Record<string, unknown> = {}) => ({
  tag_name: tag,
  html_url: `https://github.com/Memnox/memnox-desktop/releases/tag/${tag}`,
  assets: assets.map((name) => ({ name, browser_download_url: `https://github.com/Memnox/memnox-desktop/releases/download/${tag}/${name}` })),
  ...over,
});

const LISTED = JSON.stringify([
  release('app-v0.1.4', ['Memnox-setup.exe', 'Memnox_0.1.4_amd64.deb']),
  release('app-v0.2.0', ['Memnox-setup.exe', 'Memnox_0.2.0_amd64.deb', 'Memnox.dmg']),
  release('app-v0.3.0', ['Memnox.dmg']),
  release('app-v0.9.0', ['Memnox-setup.exe'], { draft: true }),
  release('v9.9.9', ['Memnox-setup.exe']),
]);

describe('reading what is out', () => {
  it('takes the newest release that carries this system, the installer on Windows and the page on Linux', () => {
    expect(newestAppRelease(LISTED, 'windows')).toEqual({ version: '0.2.0', url: 'https://github.com/Memnox/memnox-desktop/releases/download/app-v0.2.0/Memnox-setup.exe' });
    expect(newestAppRelease(LISTED, 'linux')).toEqual({ version: '0.2.0', url: 'https://github.com/Memnox/memnox-desktop/releases/tag/app-v0.2.0' });
    expect(newestAppRelease(LISTED, 'other')).toBeUndefined();
  });

  it('passes over a draft, another tag, a link that is not https and an answer it cannot read', () => {
    expect(newestAppRelease('not json', 'windows')).toBeUndefined();
    expect(newestAppRelease('{}', 'windows')).toBeUndefined();
    const plain = JSON.stringify([{ tag_name: 'app-v1.0.0', assets: [{ name: 'Memnox-setup.exe', browser_download_url: 'http://elsewhere.test/x.exe' }] }]);
    expect(newestAppRelease(plain, 'windows')).toBeUndefined();
  });

  it('reads the runtime npm calls latest, and nothing that is not a version', () => {
    expect(newestRuntimeVersion('{"name":"memnox","version":"0.16.2"}')).toBe('0.16.2');
    expect(newestRuntimeVersion('{"version":"latest"}')).toBeUndefined();
    expect(newestRuntimeVersion('<html>')).toBeUndefined();
  });

  it('offers only what is newer than what runs, and never the version put off', () => {
    expect(isNewer('0.2.0', '0.1.4')).toBe(true);
    expect(isNewer('0.1.4', '0.1.4')).toBe(false);
    expect(offered('0.2.0', '0.1.4', undefined)).toBe(true);
    expect(offered('0.2.0', '0.1.4', '0.2.0')).toBe(false);
    expect(offered('0.3.0', '0.1.4', '0.2.0')).toBe(true);
    expect(offered('0.2.0', undefined, undefined)).toBe(false);
    expect(offered(undefined, '0.1.4', undefined)).toBe(false);
  });
});

function world(over: Partial<UpdateFacts> = {}, lists: Partial<Record<'app' | 'runtime', string>> = { app: LISTED, runtime: '{"version":"0.16.0"}' }) {
  const skipped = new Map<string, string>();
  const opened: string[] = [];
  const asked: string[] = [];
  const feed: ReleaseFeed = {
    read: async (list) => {
      asked.push(list);
      return lists[list];
    },
  };
  const facts: UpdateFacts = {
    platform: 'windows',
    appVersion: async () => '0.1.4',
    runtimeVersion: async () => '0.15.0',
    skipped: (kind) => skipped.get(kind),
    putOff: (kind, version) => void skipped.set(kind, version),
    updateRuntime: async () => undefined,
    openPage: (url) => void opened.push(url),
    ...over,
  };
  return { updates: new Updates(feed, facts), skipped, opened, asked };
}

describe('offering an update', () => {
  it('offers a newer app and a newer service side by side', async () => {
    const { updates } = world();
    await updates.look();
    expect(updates.offers.map((offer) => [offer.kind, offer.version])).toEqual([
      ['app', '0.2.0'],
      ['runtime', '0.16.0'],
    ]);
    expect(updates.offers.map(UpdateLines.title)).toEqual(['Memnox 0.2.0 is out', 'Memnox service 0.16.0 is out']);
    expect(updates.offers.map(UpdateLines.action)).toEqual(['Download', 'Update']);
  });

  it('offers nothing when both are current, the service is away, or a list cannot be read', async () => {
    const current = world({ appVersion: async () => '0.2.0', runtimeVersion: async () => '0.16.0' });
    await current.updates.look();
    expect(current.updates.offers).toEqual([]);
    const away = world({ runtimeVersion: async () => undefined, appVersion: async () => undefined });
    await away.updates.look();
    expect(away.updates.offers).toEqual([]);
    // With no version to compare, nothing is fetched at all.
    expect(away.asked).toEqual([]);
    const unread = world({}, {});
    await unread.updates.look();
    expect(unread.updates.offers).toEqual([]);
  });

  it('with no feed it asks nothing and offers nothing, as a preview does', async () => {
    const updates = new Updates(undefined, world().updates['facts' as never]);
    await updates.look();
    expect(updates.offers).toEqual([]);
  });

  it('opens the installer for the app and leaves the offer standing until Later', async () => {
    const { updates, opened, skipped } = world();
    await updates.look();
    const app = updates.offers[0];
    if (app === undefined) throw new Error('no offer');
    await updates.update(app);
    expect(opened).toEqual(['https://github.com/Memnox/memnox-desktop/releases/download/app-v0.2.0/Memnox-setup.exe']);
    expect(updates.offers.map((offer) => offer.kind)).toEqual(['app', 'runtime']);
    updates.later(app);
    expect(skipped.get('app')).toBe('0.2.0');
    expect(updates.offers.map((offer) => offer.kind)).toEqual(['runtime']);
    await updates.look();
    expect(updates.offers.map((offer) => offer.kind)).toEqual(['runtime']);
  });

  it('updates the service in place and takes the offer away once it answers again', async () => {
    let ran = 0;
    const { updates } = world({ updateRuntime: async () => void (ran += 1) });
    await updates.look();
    const runtime = updates.offers[1];
    if (runtime === undefined) throw new Error('no offer');
    const running = updates.update(runtime);
    expect(updates.busy).toBe('runtime');
    await running;
    expect(ran).toBe(1);
    expect(updates.busy).toBeUndefined();
    expect(updates.offers.map((offer) => offer.kind)).toEqual(['app']);
  });

  it('says why an update stopped short and keeps the offer to try again', async () => {
    const { updates } = world({ updateRuntime: async () => 'The Memnox service would not restart.' });
    await updates.look();
    const runtime = updates.offers[1];
    if (runtime === undefined) throw new Error('no offer');
    await updates.update(runtime);
    expect(updates.failed).toBe('The Memnox service would not restart.');
    expect(updates.offers.map((offer) => offer.kind)).toEqual(['app', 'runtime']);
    expect(UpdateLines.failed(updates.failed ?? '')).toBe('The update did not finish: The Memnox service would not restart.');
  });

  it('keeps every word free of dashes', () => {
    const offers = [
      { kind: 'app', version: '0.2.0' },
      { kind: 'runtime', version: '0.16.0' },
    ] as const;
    for (const line of [...offers.flatMap((offer) => [UpdateLines.title(offer), UpdateLines.detail(offer)]), UpdateLines.updatingRuntime, UpdateLines.failed('x')]) {
      expect(line).not.toMatch(/[\u2014\u2013]| - /);
    }
  });
});
