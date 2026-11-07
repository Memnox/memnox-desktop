import { invoke } from '@tauri-apps/api/core';
import type { HttpTransport, PersonCredentialStore } from '../../core/application/ports/workspace-inbox';
import type { WorkspaceCredential } from '../../core/domain/workspace-wire';
import { TAURI_COMMAND } from './tauri-commands';

/** Memnox Cloud through `cloud.rs`, which reaches only the cloud's own host, so the webview needs no network of its own. */
export const tauriCloud: HttpTransport = {
  send: (method, path, body, token) => invoke<{ status: number; body: string }>(TAURI_COMMAND.cloudSend, { method, path, body: body ?? null, token: token ?? null }),
};

/** The person's credential in Credential Manager or the Secret Service, through `cloud.rs`. */
export const tauriPersonCredential: PersonCredentialStore = {
  async load() {
    const text = await invoke<string | null>(TAURI_COMMAND.personCredentialLoad);
    if (text === null) return undefined;
    try {
      return JSON.parse(text) as WorkspaceCredential;
    } catch {
      return undefined;
    }
  },
  save: (credential) => invoke<void>(TAURI_COMMAND.personCredentialSave, { credential: JSON.stringify(credential) }),
  delete: () => invoke<void>(TAURI_COMMAND.personCredentialDelete),
};
