import { describe, expect, it } from 'vitest';
import { commands, inspectedItem, inspectorAlone, inspectorSearch, routeFrom, shellLayout, widthClass } from '../src/core/domain/destinations';

describe('the shell at each breakpoint', () => {
  it('keeps the inspector beside the page at 1280', () => {
    expect(widthClass(1280)).toBe('wide');
    expect(shellLayout(widthClass(1280), false)).toEqual({ sidebar: 'labels', inspector: 'beside', canFold: true });
    expect(shellLayout(widthClass(1280), true).sidebar).toBe('rail');
  });

  it('floats the inspector as a drawer at 1000', () => {
    expect(widthClass(1000)).toBe('medium');
    expect(shellLayout(widthClass(1000), false)).toEqual({ sidebar: 'labels', inspector: 'drawer', canFold: true });
  });

  it('folds the sidebar to icons at 760', () => {
    expect(widthClass(760)).toBe('narrow');
    expect(shellLayout(widthClass(760), false)).toEqual({ sidebar: 'rail', inspector: 'full', canFold: false });
  });

  it('turns the sidebar into a sheet at 480', () => {
    expect(widthClass(480)).toBe('compact');
    expect(shellLayout(widthClass(480), true)).toEqual({ sidebar: 'sheet', inspector: 'full', canFold: false });
  });
});

describe('an inspector popped out', () => {
  it('opens on the page it came from with only the item drawn', () => {
    const search = inspectorSearch({ destination: 'connectors', tab: 'mcp' }, 'git hub');
    expect(search).toBe('?dest=connectors&tab=mcp&inspect=git%20hub&alone=1');
    expect(routeFrom(search)).toEqual({ destination: 'connectors', tab: 'mcp' });
    expect(inspectedItem(search)).toBe('git hub');
    expect(inspectorAlone(search)).toBe(true);
    expect(inspectorAlone('?dest=mcp&tab=servers')).toBe(false);
  });
});

describe('the palette', () => {
  it('reaches the Memory and Files pages by the names the sidebar gives them', () => {
    const titles = commands(() => true).map((each) => each.title);
    expect(titles).toEqual(expect.arrayContaining(['Memory', 'Files', 'Activity', 'Rules']));
    expect(titles).not.toContain('Sources');
    // The Memory row's three tabs are each a command, as in the Mac's palette.
    expect(titles).toEqual(expect.arrayContaining(['Map', 'Layers']));
  });

  it('lists the number key beside each destination', () => {
    const keyed = commands(() => true).filter((each) => each.key !== undefined).map((each) => `${each.key} ${each.title}`);
    expect(keyed).toEqual(['1 Home', '2 Needs you', '3 Sessions', '4 Agents', '5 Projects', '6 Rules', '7 Hand over', '8 Activity', '9 Memory']);
  });
});
