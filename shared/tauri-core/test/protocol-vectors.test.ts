import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { confirmationMessage, DAEMON_EVENT, DAEMON_METHOD, HOLD_ANSWER } from '@memnox/core/wire';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

interface Vectors {
  version: number;
  messages: { name: string; inputs: Record<string, string | null>; message: string }[];
  values: Record<string, string[]>;
}

const shared = fileURLToPath(new URL('../../vectors/protocol.json', import.meta.url));
const vectors = JSON.parse(readFileSync(shared, 'utf8')) as Vectors;

describe('the wire this app imports', () => {
  it('builds every confirmation in shared/vectors byte for byte', () => {
    const confirms = vectors.messages.filter((vector) => vector.name.startsWith('confirm'));
    expect(confirms.length).toBeGreaterThan(0);
    for (const { inputs, message } of confirms) {
      const edited = inputs['edited'] ?? undefined;
      const editedTo = inputs['editedTo'] ?? undefined;
      expect(confirmationMessage(inputs['subject'] ?? '', inputs['answer'] ?? '', edited, editedTo)).toBe(message);
    }
  });

  it('is the same runtime as the vectors were written by', () => {
    expect(Object.values(DAEMON_METHOD)).toEqual(vectors.values['methods']);
    expect(Object.values(DAEMON_EVENT)).toEqual(vectors.values['events']);
    expect(Object.values(HOLD_ANSWER)).toEqual(vectors.values['holdAnswers']);
  });
});

/** Every file under a folder, so the core's imports are read whole. */
function filesUnder(folder: string): string[] {
  return readdirSync(folder).flatMap((name) => {
    const path = join(folder, name);
    return statSync(path).isDirectory() ? filesUnder(path) : [path];
  });
}

describe('the core', () => {
  it('imports no screen and no Tauri, so it is tested headless and shared by every desktop', () => {
    const core = fileURLToPath(new URL('../src/core', import.meta.url));
    const imports = filesUnder(core)
      .filter((file) => file.endsWith('.ts'))
      .flatMap((file) => ts.preProcessFile(readFileSync(file, 'utf8')).importedFiles.map((imported) => imported.fileName));
    expect(imports.filter((specifier) => !specifier?.startsWith('.') && specifier !== '@memnox/core/wire')).toEqual([]);
  });
});
