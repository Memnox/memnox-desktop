import { describe, expect, it } from 'vitest';
import { islandScreenOptions, parseIslandScreen, shownIslandScreen, storedIslandScreen } from '../src/core/domain/island-screen';

describe('the display the island hangs from', () => {
  it('reads back what it kept, and the main display for anything else', () => {
    expect(storedIslandScreen(parseIslandScreen('pointer'))).toBe('pointer');
    expect(parseIslandScreen('display:DP-1')).toEqual({ kind: 'display', id: 'DP-1' });
    expect(parseIslandScreen('display:')).toEqual({ kind: 'notch' });
    expect(parseIslandScreen(undefined)).toEqual({ kind: 'notch' });
  });

  it('lists the two fixed choices before each display, and shows a gone display as the main one', () => {
    const displays = [{ id: 'HDMI-1', name: 'Display 2, 2560 by 1440' }];
    expect(islandScreenOptions(displays).map((option) => option.value)).toEqual(['notch', 'pointer', 'display:HDMI-1']);
    expect(shownIslandScreen('display:HDMI-1', displays)).toBe('display:HDMI-1');
    expect(shownIslandScreen('display:gone', displays)).toBe('notch');
  });
});
