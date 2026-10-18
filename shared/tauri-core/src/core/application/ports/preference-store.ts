/** Where a choice is kept between launches: the webview's own storage here, a memory in tests. */
export interface PreferenceStore {
  load(key: string): string | null;
  save(key: string, value: string): void;
}
