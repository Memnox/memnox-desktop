import { describe, expect, it } from 'vitest';
import { AgentPresetLines, startedPack } from '../src/core/domain/agent-presets';

/** As the Mac's `AgentPresetsTests` pins it. */
describe('one agent started on a pack', () => {
  const packs = [{ id: 'safe-defaults', name: 'Safe defaults' }, { id: 'read-only-agents', name: 'Read-only agents' }];

  it('reads the pack an agent was started on', () => {
    const rules = [{ name: 'pack-read-only-agents-write-ask-for-cursor' }, { name: 'pack-safe-defaults-delete-ask' }];
    expect(startedPack(rules, 'cursor', packs)?.id).toBe('read-only-agents');
    expect(startedPack(rules, 'claude-code', packs)).toBeUndefined();
    expect(AgentPresetLines.line(undefined)).toBe('Follows your general rules.');
    expect(AgentPresetLines.line(packs[1])).toBe('Started on Read-only agents.');
  });
});
