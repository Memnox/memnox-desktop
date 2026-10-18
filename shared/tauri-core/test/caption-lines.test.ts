import type { DaemonEvent, DaemonResponse } from '@memnox/core/wire';
import { describe, expect, it } from 'vitest';
import { RequestIds } from '../src/core/application/request-ids';
import { Signer } from '../src/core/application/signer';
import { Talking } from '../src/core/application/talking';
import { displayCaption, keyCaption, readingCaption } from '../src/core/domain/caption-lines';
import { HandTimer, held, PersonKey, RecordingSpeaker, registered, ScriptedDaemon } from './doubles';

const show = (display: string, extra: Partial<DaemonEvent> = {}): DaemonEvent => ({ ...held('s1'), kind: 'show', display, ...extra }) as DaemonEvent;

describe('the caption line', () => {
  it('names the tool being read as a person would', () => {
    expect(readingCaption('mcp__memnox-operator__sessions')).toBe('reading sessions');
    expect(readingCaption(undefined)).toBe('reading the machine');
  });

  it("names each system's own key where the Mac says Touch ID, cut to one line", () => {
    expect(keyCaption('windows', 'allow the push once')).toBe('Windows Hello to allow the push once');
    expect(keyCaption('linux', 'allow the push once')).toBe('Your password to allow the push once');
    expect(keyCaption('windows', 'allow npm publish for this session: publish the package to the registry')).toBe(
      'Windows Hello to allow npm publish for…',
    );
  });

  it('says what a display under way does, and nothing for one that shows at once', () => {
    expect(displayCaption(show('type'))).toBe('typing it in');
    expect(displayCaption(show('prefill'))).toBe('typing it in');
    expect(displayCaption(show('launch'))).toBe('starting it');
    expect(displayCaption(show('app', { title: 'Cursor' }))).toBe('opening Cursor');
    expect(displayCaption(show('close'))).toBe('closing it');
    expect(displayCaption(show('interrupt'))).toBe('stopping it');
    expect(displayCaption(show('press'))).toBe('answering it');
    expect(displayCaption(show('summary'))).toBeUndefined();
  });

  it('shows the tool while the brain reads and clears once the turn ends', async () => {
    const daemon = new ScriptedDaemon({
      'register-key': registered,
      ask: (request): DaemonResponse[] => [
        { id: request.id, ok: true, chunk: { kind: 'tool', tool: 'mcp__composio__gmail' } },
        { id: request.id, ok: true, chunk: { kind: 'text', text: 'You have two new mails.' } },
        { id: request.id, ok: true, chunk: { kind: 'done' } },
      ],
    });
    const ids = new RequestIds();
    const talking = new Talking(daemon, new RecordingSpeaker(), new Signer(daemon, new PersonKey(), ids), ids, { timer: new HandTimer().start });
    const seen: (string | undefined)[] = [];
    talking.observe(() => seen.push(talking.state.caption));
    await talking.heard('any new mail');
    expect(seen).toContain('reading gmail');
    expect(talking.state.caption).toBeUndefined();
  });

  it('carries a caption set from outside the talk until it is cleared', () => {
    const daemon = new ScriptedDaemon({ 'register-key': registered });
    const ids = new RequestIds();
    const talking = new Talking(daemon, new RecordingSpeaker(), new Signer(daemon, new PersonKey(), ids), ids, { timer: new HandTimer().start });
    talking.captioned('typing it in');
    expect(talking.state.caption).toBe('typing it in');
    talking.captioned(undefined);
    expect(talking.state.caption).toBeUndefined();
  });
});
