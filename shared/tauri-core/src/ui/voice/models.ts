/**
 * Whether the voice's models are on this computer, read by the core's turns before they open the
 * microphone, and set by the island once Rust says so or the install finished.
 */
class VoiceModels {
  private on = false;

  get installed(): boolean {
    return this.on;
  }

  set(installed: boolean): void {
    this.on = installed;
  }
}

export const voiceModels = new VoiceModels();
