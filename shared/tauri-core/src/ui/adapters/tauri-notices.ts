import { isPermissionGranted, requestPermission, sendNotification } from '@tauri-apps/plugin-notification';
import type { NoticeSystem } from '../../core/application/held-call-notices';

/** The system's notifications through `tauri-plugin-notification`; a press on one is answered in `notices.rs`. */
export const tauriNotices: NoticeSystem = {
  granted: () => isPermissionGranted().catch(() => false),
  ask: () => requestPermission().then((answer) => answer === 'granted', () => false),
  post: (notice) => sendNotification({ title: notice.title, body: notice.body }),
};
