/**
 * The key a yes is signed with, guarded by the operating system: a TPM key behind Windows Hello,
 * or a Secret Service key behind a local check on Linux. An agent running as the same user can
 * raise the prompt but never finish it, which is the whole reason a yes is signed.
 */
export interface ConfirmKey {
  /** The public half as the daemon registers it: a base64 X9.63 P-256 point, undefined when there is no key here. */
  publicPoint(): Promise<string | undefined>;
  /** A base64 DER ECDSA signature over exactly these words, or undefined when the person declined or cancelled. */
  sign(message: string, reason: string): Promise<string | undefined>;
}
