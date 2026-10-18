/** The control that has the keyboard in whatever app is in front, as the platform reads it. */
export interface Focus {
  /** The app's executable name, lowercased: "slack", "code", "chrome". */
  readonly app?: string;
  readonly title?: string;
  /** A password field, which is never written into by voice. */
  readonly secure: boolean;
  /** Text selected there, which dictation then edits by instruction. */
  readonly selection?: string;
}

/** Types into the app in front, as the platform layer in Rust does it: SendInput, wtype, ydotool or xdotool. */
export interface Typist {
  focus(): Promise<Focus>;
  type(text: string): Promise<void>;
  /** Takes `remove` characters back from before the cursor, then types `add`, for words revised live. */
  revise(remove: number, add: string): Promise<void>;
  /** Leaves the text on the clipboard, for when the app it was meant for left the front. */
  copy(text: string): Promise<void>;
}
