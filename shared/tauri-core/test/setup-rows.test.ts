import { describe, expect, it } from 'vitest';
import { keyPromptStep, permissionSteps, type PermissionFacts } from '../src/core/domain/permission-steps';
import { editorRow } from '../src/core/domain/setup-steps';
import { DONE } from '../src/core/domain/step-state';

const wayland: PermissionFacts = { platform: 'linux', session: 'wayland', microphone: 'allowed', typing: true };

function see(facts: PermissionFacts) {
  return permissionSteps(facts).find((step) => step.id === 'see');
}

describe('seeing the screen, with no grant claimed', () => {
  it('needs the portal on Wayland when none answers', () => {
    expect(see({ ...wayland, seeing: { portal: false, accessibility: true } })?.state.kind).toBe('needs');
  });

  it('needs the accessibility bus where it is off', () => {
    const step = see({ ...wayland, seeing: { portal: true, accessibility: false } });
    expect(step?.state.kind).toBe('needs');
    expect(step?.guide.join(' ')).toContain('toolkit-accessibility');
  });

  it('leaves the ask to the desktop prompt when both are there', () => {
    expect(see({ ...wayland, seeing: { portal: true, accessibility: true } })?.state).toEqual(DONE);
  });
});

describe('the prompt before the key signs', () => {
  it('needs a polkit agent on Linux', () => {
    expect(keyPromptStep(DONE, { ...wayland, polkitAgent: false }).kind).toBe('needs');
  });

  it('keeps the key step where an agent runs or the system is not Linux', () => {
    expect(keyPromptStep(DONE, { ...wayland, polkitAgent: true })).toEqual(DONE);
    expect(keyPromptStep(DONE, { platform: 'windows', session: 'desktop', microphone: 'allowed', typing: true, polkitAgent: false })).toEqual(DONE);
  });
});

describe('Memnox in your editor', () => {
  it('shows only where an editor is', () => {
    expect(editorRow({ present: false, withExtension: [] }).shown).toBe(false);
    expect(editorRow(undefined).shown).toBe(false);
  });

  it('waits until the daemon puts the extension in, then is done', () => {
    expect(editorRow({ present: true, withExtension: [] }).state.kind).toBe('waiting');
    const landed = editorRow({ present: true, withExtension: ['.cursor/extensions'] });
    expect(landed.state).toEqual(DONE);
    expect(landed.detail).toContain('Restart the editor');
  });
});
