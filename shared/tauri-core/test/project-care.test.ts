import { describe, expect, it } from 'vitest';
import { carePack, PROJECT_EXAMPLES, projectCareOf, ProjectWhy } from '../src/core/domain/project-care';

/** How careful agents are in one project, as the Mac's `ProjectCareTests` pins it. */
describe('a project’s care', () => {
  it('is relaxed with no starter rules of its own', () => {
    expect(projectCareOf([])).toBe('relaxed');
    expect(projectCareOf([{ name: 'my-own-rule' }])).toBe('relaxed');
    expect(carePack('relaxed')).toBeUndefined();
  });

  it('names the strictest pack started here', () => {
    expect(projectCareOf([{ name: 'pack-safe-defaults-delete-ask' }])).toBe('careful');
    expect(projectCareOf([{ name: 'pack-safe-defaults-delete-ask' }, { name: 'pack-read-only-agents-write-ask' }])).toBe('strict');
    expect([carePack('careful'), carePack('strict')]).toEqual(['safe-defaults', 'read-only-agents']);
  });

  it('shows three examples each with its own care', () => {
    expect(PROJECT_EXAMPLES.map((example) => example.care)).toEqual(['relaxed', 'careful', 'strict']);
    expect(ProjectWhy.lines).toHaveLength(4);
  });
});
