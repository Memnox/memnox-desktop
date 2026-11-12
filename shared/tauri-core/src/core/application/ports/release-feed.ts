/** Which list of releases is read: the desktop app's on GitHub, or the runtime's newest on npm. */
export type ReleaseList = 'app' | 'runtime';

/** Where the app learns a newer Memnox is out. The adapter reaches two fixed addresses and nothing else. */
export interface ReleaseFeed {
  /** The list's answer as it came, or undefined when it could not be read. */
  read(list: ReleaseList): Promise<string | undefined>;
}
