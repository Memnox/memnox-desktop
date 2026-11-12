import type { Platform } from './platform';
import { isAtLeast } from './runtime-state';

/**
 * A newer Memnox a person can move to, as the Mac's `AppUpdates` offers one: the app itself, read from this
 * repo's releases on GitHub, or the Memnox service, read from the package published to npm. Nothing here decides
 * to update. It only says a newer one is out, and the person presses Update or Later.
 */
export type UpdateKind = 'app' | 'runtime';

export interface UpdateOffer {
  readonly kind: UpdateKind;
  /** The version on offer, which Later puts off without putting off the ones after it. */
  readonly version: string;
  /** Where the app's installer is fetched; the service updates in place and has none. */
  readonly url?: string;
}

/** A release of the app as its feed lists it: the version and where this system gets it. */
export interface AppRelease {
  readonly version: string;
  readonly url: string;
}

/** The tag `release-app.yml` releases from, `app-v<version>`. */
const TAG_PREFIX = 'app-v';
/** The installer every Windows release carries under one name, as `release-app.yml` copies it. */
const WINDOWS_INSTALLER = 'Memnox-setup.exe';
/** What marks a release as carrying the Linux app, whichever package a person then takes from its page. */
const LINUX_ASSET = /\.(deb|rpm|AppImage)$/;

/** How often a running app looks again, the Mac's `updateCheckSeconds`. */
export const UPDATE_CHECK_MS = 6 * 60 * 60 * 1000;

/** Whether `version` is one the build at `running` should move to. */
export function isNewer(version: string, running: string): boolean {
  return !isAtLeast(running, version);
}

/**
 * The newest release carrying this system's app, from GitHub's list of releases, as the Mac's `AppRelease.newest`:
 * a draft, a tag that is not the app's, or a release this system's installer was never added to is passed over.
 * Windows is handed the installer itself; Linux is handed the release's page, where each package is listed.
 */
export function newestAppRelease(body: string, platform: Platform): AppRelease | undefined {
  const listed = parsed(body);
  if (!Array.isArray(listed)) return undefined;
  let newest: AppRelease | undefined;
  for (const release of listed) {
    if (!isObject(release) || release['draft'] === true) continue;
    const tag = release['tag_name'];
    if (typeof tag !== 'string' || !tag.startsWith(TAG_PREFIX) || tag.length === TAG_PREFIX.length) continue;
    const url = releaseUrl(release, platform);
    if (url === undefined) continue;
    const version = tag.slice(TAG_PREFIX.length);
    if (newest === undefined || isNewer(version, newest.version)) newest = { version, url };
  }
  return newest;
}

function releaseUrl(release: Record<string, unknown>, platform: Platform): string | undefined {
  const assets = Array.isArray(release['assets']) ? release['assets'].filter(isObject) : [];
  const named = (test: (name: string) => boolean) => assets.find((asset) => typeof asset['name'] === 'string' && test(asset['name']));
  if (platform === 'windows') return https(named((name) => name === WINDOWS_INSTALLER)?.['browser_download_url']);
  if (platform === 'linux') return named((name) => LINUX_ASSET.test(name)) === undefined ? undefined : https(release['html_url']);
  return undefined;
}

/** A link is opened in the browser, so only an https one is ever kept. */
function https(value: unknown): string | undefined {
  return typeof value === 'string' && value.startsWith('https://') ? value : undefined;
}

/** The version npm says is the newest published runtime, from the registry's answer for `memnox/latest`. */
export function newestRuntimeVersion(body: string): string | undefined {
  const answer = parsed(body);
  const version = isObject(answer) ? answer['version'] : undefined;
  return typeof version === 'string' && /^\d+\.\d+\.\d+/.test(version) ? version : undefined;
}

/**
 * What to offer: only a version newer than the one running, and never the one the person put off, though a newer
 * one after it is offered again, as the Mac's `AppUpdates.offer`.
 */
export function offered(newest: string | undefined, running: string | undefined, skipped: string | undefined): boolean {
  return newest !== undefined && running !== undefined && isNewer(newest, running) && newest !== skipped;
}

/** The words an offer says, the same under the island and on Home. */
export const UpdateLines = {
  update: 'Update',
  download: 'Download',
  later: 'Later',
  updatingRuntime: 'Updating the Memnox service',
  title: (offer: UpdateOffer): string => (offer.kind === 'app' ? `Memnox ${offer.version} is out` : `Memnox service ${offer.version} is out`),
  detail: (offer: UpdateOffer): string =>
    offer.kind === 'app'
      ? 'A newer Memnox app is ready. Download it and run the installer, and it replaces this one.'
      : 'A newer Memnox service is ready. Updating takes a moment, and your agents carry on under the same rules.',
  /** What the press says: the app is fetched in the browser, the service updates in place. */
  action: (offer: UpdateOffer): string => (offer.kind === 'app' ? UpdateLines.download : UpdateLines.update),
  failed: (why: string): string => `The update did not finish: ${why}`,
} as const;

function parsed(body: string): unknown {
  try {
    return JSON.parse(body) as unknown;
  } catch {
    return undefined;
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
