import { describe, expect, it } from 'vitest';

import { activityWords } from '../src/core/domain/activity-words';

const home = '/Users/someone/Documents/Memnox-saas/memnox-client';

describe('activityWords', () => {
  it('names the file and the project it sits in', () => {
    expect(activityWords({ operation: 'file.edit', target: `${home}/apps/app/components/page/form-parts.tsx` })).toBe('Changed form-parts.tsx in memnox-client');
  });

  it('says files in a project when the target is a folder', () => {
    expect(activityWords({ operation: 'filesystem.write', target: `${home}/apps/app/.` })).toBe('Changed files in memnox-client');
  });

  it('falls back to the folder a file sits in when nothing marks a project', () => {
    expect(activityWords({ operation: 'filesystem.read', target: '/etc/hosts' })).toBe('Read hosts in etc');
  });

  it('says commands, git and the web in plain words', () => {
    expect(activityWords({ operation: 'shell.exec', target: 'npm run build' })).toBe('Ran npm');
    expect(activityWords({ operation: 'git.push', target: 'origin main' })).toBe('Pushed');
    expect(activityWords({ operation: 'http.request', target: 'https://api.github.com/repos' })).toBe('Reached api.github.com');
  });

  it('keeps an action it does not know as written', () => {
    expect(activityWords({ operation: 'cli.ask', target: 'me' })).toBe('cli.ask me');
    expect(activityWords({ operation: 'vault.unseal' })).toBe('vault.unseal');
  });
});
