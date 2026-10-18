import type { FloatingCard } from '../../../core/domain/floating-cards';

/** The cards the preview draws with no daemon behind them: cards.html?preview=summary, walk or trace. */
export function previewCard(scene: string): FloatingCard | undefined {
  switch (scene) {
    case 'summary':
      return {
        kind: 'summary',
        title: 'Island restyle for Windows and Linux',
        agent: 'agt_claude-code',
        text: '## Done\n- Ported the **tray panel** and the tool page\n- Every work card laid out as its tool lays it out\n\nRan `pnpm test`, all 214 pass. See [the pull request](https://github.com/memnox/desktop/pull/412).',
        files: [
          { path: 'shared/tauri-core/src/ui/tray/TrayPanel.tsx', added: 212, removed: 0 },
          { path: 'shared/tauri-core/src/ui/Cards.tsx', added: 41, removed: 165 },
          { path: 'shared/tauri-core/src-tauri/src/tray.rs', added: 96, removed: 38 },
        ],
        excerpt: {
          path: 'shared/tauri-core/src-tauri/src/tray.rs',
          lines: [' pub fn build(app: &App) -> tauri::Result<()> {', '-    let show = MenuItem::with_id(app, SHOW, "Show Memnox", true, None::<&str>)?;', '+    let panel = panel::create(app)?;', '+    tray = tray.show_menu_on_left_click(false);', '     Ok(())'],
        },
        sessionId: 'ses_preview',
        host: { app: 'Cursor' },
      };
    case 'walk':
      return {
        kind: 'walk',
        title: 'What changed in the tray',
        agent: 'agt_codex',
        pages: [
          {
            path: 'shared/tauri-core/src-tauri/src/tray.rs',
            note: 'The tray now opens its own panel beside the icon instead of a native menu, and keeps the menu for a right click.',
            added: 96,
            removed: 38,
            lines: [' let tray = TrayIconBuilder::with_id("memnox")', '-    .menu(&menu);', '+    .menu(&menu)', '+    .show_menu_on_left_click(false);'],
          },
          { path: 'shared/tauri-core/src/ui/tray/TrayPanel.tsx', note: 'The panel itself.', added: 212, lines: [] },
          { path: 'shared/tauri-core/src/core/domain/menu-panel.ts', note: 'Where the panel goes.', added: 120, lines: [] },
        ],
        sessionId: 'ses_preview',
        host: { app: 'Terminal' },
      };
    case 'trace':
      return {
        kind: 'trace',
        title: 'Why was that slow?',
        trace: {
          totalMs: 4200,
          rows: [
            { name: 'ask', depth: 0, offsetMs: 0, durationMs: 4200, status: 'ok' },
            { name: 'Hearing', depth: 1, offsetMs: 0, durationMs: 900, status: 'ok' },
            { name: 'brain claude-code', depth: 1, offsetMs: 900, durationMs: 2600, status: 'ok' },
            { name: 'memnox_sessions', depth: 2, offsetMs: 1100, durationMs: 300, status: 'ok' },
            { name: 'git push', depth: 2, offsetMs: 1500, durationMs: 40, status: 'refused' },
            { name: 'linear comment', depth: 2, offsetMs: 1700, durationMs: 800, status: 'error' },
            { name: 'Speaking', depth: 1, offsetMs: 3500, durationMs: 700, status: 'ok' },
          ],
        },
      };
    default:
      return undefined;
  }
}
