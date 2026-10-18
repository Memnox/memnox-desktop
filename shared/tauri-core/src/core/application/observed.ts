/** A use case a screen redraws from: it tells every listener when its state changed, and nothing more. */
export class Observed {
  private readonly listeners = new Set<() => void>();

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  protected changed(): void {
    for (const listener of this.listeners) listener();
  }
}

/** How long to wait, injected so a test runs a poll of minutes in no time. */
export type Sleep = (ms: number) => Promise<void>;
