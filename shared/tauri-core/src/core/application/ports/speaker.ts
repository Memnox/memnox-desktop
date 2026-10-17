/** The voice: Kokoro through sherpa-onnx in Rust, a recorder in tests. */
export interface Speaker {
  /** Puts one sentence after whatever is already being said, and returns at once. */
  queue(sentence: string): void;
  /** Resolves once everything queued has been said, or stopped. */
  drained(): Promise<void>;
  /** Stops now and drops the rest, because the person talked over it or answered elsewhere. */
  stop(): void;
}
