import { describe, expect, it } from 'vitest';
import { AgentHomes, sessionHome } from '../src/core/application/agent-homes';
import type { PreferenceStore } from '../src/core/application/ports/preference-store';
import { AgentHomesLines, chosenHome, homeLaunch, homeReady, pickedPlan, type FoundHome } from '../src/core/domain/agent-homes';

class MemoryStore implements PreferenceStore {
  readonly kept = new Map<string, string>();
  load = (key: string) => this.kept.get(key) ?? null;
  save = (key: string, value: string) => void this.kept.set(key, value);
}

const found: FoundHome[] = [{ kind: 'windows-terminal' }, { kind: 'powershell' }, { kind: 'vscode', memnoxExtension: true, claudeCode: true }];

describe('where your agents run', () => {
  it('offers the first app installed until the person answers, then keeps what they picked or cleared', () => {
    expect(chosenHome(null, false, ['konsole', 'xterm'])).toBe('konsole');
    expect(chosenHome('xterm', true, ['konsole', 'xterm'])).toBe('xterm');
    expect(chosenHome('', true, ['konsole'])).toBeUndefined();
    expect(chosenHome('alacritty', true, ['konsole'])).toBeUndefined();
  });

  it('reaches the editor by the extension, Windows Terminal by its tab command and the rest by a window', () => {
    expect(homeLaunch('vscode')).toEqual({ kind: 'editor', editor: 'code' });
    expect(homeLaunch('windows-terminal')).toEqual({ kind: 'terminal', terminal: 'windows-terminal' });
    expect(homeLaunch('gnome-terminal')).toEqual({ kind: 'window', home: 'gnome-terminal' });
    expect(pickedPlan('xterm', true)).toEqual({ kind: 'none', why: 'Stay where I am is on, and xterm opens its window in front, so nothing was started' });
    expect(pickedPlan('kitty', false)).toEqual({ kind: 'window', home: 'kitty' });
  });

  it('counts a terminal ready at once and the editor once its extension and chat are in, as the Mac’s card says', () => {
    expect(homeReady({ kind: 'cmd' }, false)).toBe(true);
    expect(homeReady({ kind: 'vscode', memnoxExtension: true, claudeCode: true }, false)).toBe(false);
    expect(homeReady({ kind: 'vscode', memnoxExtension: true, claudeCode: true }, true)).toBe(true);
    expect(homeReady({ kind: 'vscode', memnoxExtension: true, claudeCode: false }, false)).toBe(true);
    expect(AgentHomesLines.picked(0, 0)).toBe('Tap the one you run Claude Code, Codex or Cursor in.');
    expect(AgentHomesLines.picked(1, 1)).toBe('All set in the app you picked.');
    expect(AgentHomesLines.picked(1, 0)).toBe('0 of 1 ready.');
    expect(AgentHomesLines.noneDetail('linux')).toBe('Memnox works with GNOME Terminal, Konsole, kitty, Alacritty, xterm and VS Code.');
  });

  it('remembers the pick where the island reads it, and the chat once it came up', async () => {
    const store = new MemoryStore();
    const opened: string[] = [];
    const homes = new AgentHomes(store, async () => found, (link) => opened.push(link));
    await homes.look();
    expect(homes.chosen).toBe('windows-terminal');
    homes.toggle('vscode');
    expect(await sessionHome(store, async () => found)).toBe('vscode');
    homes.toggle('vscode');
    expect(homes.chosen).toBeUndefined();
    expect(await sessionHome(store, async () => found)).toBeUndefined();
    homes.tryChat('vscode');
    expect(opened).toEqual(['vscode://anthropic.claude-code/open']);
    expect(homes.isTrying('vscode')).toBe(true);
    homes.chatCameUp('vscode', true);
    expect(homes.isTrying('vscode')).toBe(false);
    expect(homes.chatOpened('vscode')).toBe(true);
  });
});
