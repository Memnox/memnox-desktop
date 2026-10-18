import { isLook, type Look } from '../domain/appearance';
import type { PreferenceStore } from './ports/preference-store';

/** The keys the person's own choices are kept under, the Mac's UserDefaults keys under one prefix. */
export const PREFERENCE = {
  /** What Memnox calls the person, the Mac's owner name. */
  name: 'memnox.name',
  /** Set once the first run is finished, after which Settings stops offering Finish setup. */
  setupDone: 'memnox.setupDone',
  /** Which way the first run went, so the choice is offered once: mac or account. */
  firstRun: 'memnox.firstRunPath',
  /** Light, dark or system, for every window but the island. */
  appearance: 'memnox.appearance',
  /** The first run's spoken guide, muted from its footer. */
  guideMuted: 'memnox.onboarding.muted',
} as const;

/** The first run's two ways in, stored as the Mac stores them. */
export const FIRST_RUN = { thisComputer: 'mac', account: 'team' } as const;

/** The person's name, the look, and where the first run stands, read and written through the store. */
export class Preferences {
  constructor(private readonly store: PreferenceStore) {}

  get name(): string {
    return this.read(PREFERENCE.name) ?? '';
  }

  /** Kept as it is typed; an empty name is no name. */
  set name(name: string) {
    const kept = name.trim();
    this.write(PREFERENCE.name, kept === '' ? undefined : kept);
  }

  get setupDone(): boolean {
    return this.read(PREFERENCE.setupDone) === 'true';
  }

  finishSetup(): void {
    this.write(PREFERENCE.setupDone, 'true');
  }

  get firstRun(): string {
    return this.read(PREFERENCE.firstRun) ?? '';
  }

  set firstRun(path: string) {
    this.write(PREFERENCE.firstRun, path);
  }

  get look(): Look {
    const stored = this.read(PREFERENCE.appearance);
    return stored !== undefined && isLook(stored) ? stored : 'system';
  }

  set look(look: Look) {
    this.write(PREFERENCE.appearance, look);
  }

  get guideMuted(): boolean {
    return this.read(PREFERENCE.guideMuted) === 'true';
  }

  set guideMuted(muted: boolean) {
    this.write(PREFERENCE.guideMuted, muted ? 'true' : undefined);
  }

  private read(key: string): string | undefined {
    const value = this.store.load(key);
    return value === null || value === '' ? undefined : value;
  }

  /** An empty value is how a choice is cleared, since the store keeps strings. */
  private write(key: string, value: string | undefined): void {
    this.store.save(key, value ?? '');
  }
}
