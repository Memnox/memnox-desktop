/** The computer's power: whether it runs on the charger, and holding sleep off. */
export interface Power {
  onMains(): Promise<boolean>;
  /** Holds sleep off while on, and lets the computer sleep again when off. */
  keepAwake(on: boolean): Promise<void>;
}
