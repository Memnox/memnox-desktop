import type { PersonalSyncConflict, PersonalSyncMachine, PersonalSyncStatus } from '@memnox/core/wire';
import { KeyRound, Laptop, RefreshCw } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { SyncOutcome } from '../../../core/application/personal-sync';
import {
  COMPARE_TO_ACCEPT,
  COMPARE_TO_OFFER,
  CONFLICT_CHOICE,
  conflictCaption,
  conflictsLine,
  fingerprintGroups,
  keyWaitsLine,
  kindCount,
  lastSyncedLine,
  openedElsewhereLine,
  SYNC_WHAT,
  syncStateWord,
} from '../../../core/domain/personal-sync-lines';
import { ago } from '../../../core/domain/session-text';
import { ReadFailed, StatTile, StatusWord } from '../../app/widgets';
import { KitButton, SettingsCard, SettingsDivider, SettingsRow } from '../kit';
import { useObserved, type SettingsParts } from '../parts';

type Note = { text: string; alert: boolean } | undefined;

/** What a press said: a refusal in red, a proposal with the key that signs it, and nothing for done. */
function noteOf(outcome: SyncOutcome, waits: string): Note {
  if (outcome.kind === 'failed') return { text: outcome.why, alert: true };
  return outcome.kind === 'proposed' ? { text: waits, alert: false } : undefined;
}

/**
 * Personal sync as the runtime runs it: where it stands in its own sentence, Sync now, the key offered or
 * accepted only behind a fingerprint the person compared and signs on the island, and conflicts to choose between.
 */
export function SyncPage({ parts }: { parts: SettingsParts }) {
  const { sync } = parts;
  useObserved(sync);
  useEffect(() => void sync.refresh(), []);
  const [note, setNote] = useState<Note>(undefined);
  const status = sync.status;
  if (status === undefined) return sync.unreadable ? <ReadFailed what="personal sync" retry={() => void sync.refresh()} /> : null;
  // The plan's own sentence is all that is said there: no counts, no upsell beyond it.
  if (status.state === 'not-on-plan') return <StateCard parts={parts} status={status} note={note} said={setNote} />;
  return (
    <>
      <StateCard parts={parts} status={status} note={note} said={setNote} />
      {status.arrivedFingerprint !== undefined && <ArrivedCard parts={parts} fingerprint={status.arrivedFingerprint} said={setNote} />}
      {status.waiting.length > 0 && <WaitingCard parts={parts} waiting={status.waiting} said={setNote} />}
      <CountsCard status={status} />
      {status.conflicts > 0 && <ConflictsCard parts={parts} count={status.conflicts} said={setNote} />}
    </>
  );
}

function StateCard({ parts, status, note, said }: { parts: SettingsParts; status: PersonalSyncStatus; note: Note; said: (note: Note) => void }) {
  const { sync } = parts;
  const word = syncStateWord(status.state);
  const busy = sync.busy === 'now';
  return (
    <SettingsCard title="Personal sync">
      {status.state !== 'not-on-plan' && <p className="text-footnote text-muted">{SYNC_WHAT}</p>}
      <div className="flex flex-col gap-1.5">
        <StatusWord tone={word.tone}>{word.word}</StatusWord>
        <p className="text-body text-foreground">{status.said}</p>
        {status.state === 'ready' && <p className="text-footnote text-muted">{lastSyncedLine(ago(status.lastSyncedAt, Date.now()))}</p>}
      </div>
      {status.state === 'ready' && (
        <div className="flex gap-2">
          <KitButton kind="primary" icon={RefreshCw} disabled={busy} onClick={() => void sync.syncNow().then((outcome) => said(noteOf(outcome, '')))}>
            {busy ? 'Syncing' : 'Sync now'}
          </KitButton>
        </div>
      )}
      {note !== undefined && (
        <p role={note.alert ? 'alert' : 'status'} className={`text-footnote ${note.alert ? 'text-destructive' : 'text-foreground'}`}>
          {note.text}
        </p>
      )}
    </SettingsCard>
  );
}

/** Six groups of five digits, large and monospaced, so two screens read side by side. */
function FingerprintDigits({ fingerprint }: { fingerprint: string }) {
  return (
    <div className="grid w-fit grid-cols-3 gap-x-5 gap-y-1.5 font-mono text-[24px] font-semibold tracking-[2px] text-foreground tabular-nums" aria-label={`Fingerprint ${fingerprint}`}>
      {fingerprintGroups(fingerprint).map((group, index) => (
        <span key={`${index}-${group}`}>{group}</span>
      ))}
    </div>
  );
}

/** On the new machine: the fingerprint of the key that arrived, accepted only once compared and signed. */
function ArrivedCard({ parts, fingerprint, said }: { parts: SettingsParts; fingerprint: string; said: (note: Note) => void }) {
  const { sync, words } = parts;
  const busy = sync.busy === 'accept';
  return (
    <SettingsCard title="A sync key arrived">
      <FingerprintDigits fingerprint={fingerprint} />
      <p className="text-footnote text-muted">{COMPARE_TO_ACCEPT}</p>
      <div className="flex gap-2">
        <KitButton kind="primary" icon={KeyRound} disabled={busy} onClick={() => void sync.accept(fingerprint).then((outcome) => said(noteOf(outcome, keyWaitsLine(words.keyTitle, false))))}>
          {busy ? 'Asking' : 'Accept'}
        </KitButton>
      </div>
    </SettingsCard>
  );
}

/** On the machine holding the key: each of the person's machines waiting for it, offered only once compared and signed. */
function WaitingCard({ parts, waiting, said }: { parts: SettingsParts; waiting: readonly PersonalSyncMachine[]; said: (note: Note) => void }) {
  const { sync, words } = parts;
  return (
    <SettingsCard title="Waiting for your key">
      {waiting.map((machine, index) => (
        <div key={machine.machineId} className="flex flex-col gap-3">
          {index > 0 && <SettingsDivider full />}
          <SettingsRow icon={Laptop} title={machine.machineId} caption="Another of your machines, asking for the sync key">
            <KitButton
              kind="primary"
              icon={KeyRound}
              disabled={sync.busy === machine.machineId}
              onClick={() => void sync.offer(machine.machineId, machine.fingerprint).then((outcome) => said(noteOf(outcome, keyWaitsLine(words.keyTitle, true))))}
            >
              {sync.busy === machine.machineId ? 'Asking' : 'Offer'}
            </KitButton>
          </SettingsRow>
          <FingerprintDigits fingerprint={machine.fingerprint} />
        </div>
      ))}
      <p className="text-footnote text-muted">{COMPARE_TO_OFFER}</p>
    </SettingsCard>
  );
}

/** What this machine carries, counted by kind, with what the last run left out and what was opened elsewhere. */
function CountsCard({ status }: { status: PersonalSyncStatus }) {
  return (
    <SettingsCard title="On this machine">
      <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3">
        {status.kinds.map((count) => {
          // The count's own words, the number large and what it counts under it.
          const [value = '', ...label] = kindCount(count).split(' ');
          const words = label.join(' ');
          return <StatTile key={count.kind} value={value} label={`${words.charAt(0).toUpperCase()}${words.slice(1)}`} />;
        })}
      </div>
      {status.skipped.length > 0 && (
        <ul className="flex flex-col gap-1 text-footnote text-muted">
          {status.skipped.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
      )}
      {status.openedElsewhere.length > 0 && (
        <div className="flex flex-col gap-1">
          <p className="text-footnote text-muted">{openedElsewhereLine(status.openedElsewhere.length)}</p>
          <ul className="flex flex-col gap-0.5 font-mono text-micro text-muted">
            {status.openedElsewhere.map((repository) => (
              <li key={repository} className="truncate">
                {repository}
              </li>
            ))}
          </ul>
        </div>
      )}
    </SettingsCard>
  );
}

/** The copies a sync replaced unseen, opened here beside this machine's own, one side kept for each. */
function ConflictsCard({ parts, count, said }: { parts: SettingsParts; count: number; said: (note: Note) => void }) {
  const { sync } = parts;
  const opened = sync.conflicts;
  return (
    <SettingsCard title="Conflicts">
      <p className="text-footnote text-muted">{conflictsLine(count)}</p>
      {opened === undefined ? (
        <div className="flex gap-2">
          <KitButton disabled={sync.busy === 'conflicts'} onClick={() => void sync.loadConflicts().then((outcome) => said(noteOf(outcome, '')))}>
            {sync.busy === 'conflicts' ? 'Opening' : 'Open them'}
          </KitButton>
        </div>
      ) : (
        <>
          {opened.map((conflict) => (
            <ConflictRow key={conflict.id} parts={parts} conflict={conflict} said={said} />
          ))}
          <p className="text-footnote text-muted">{CONFLICT_CHOICE}</p>
        </>
      )}
    </SettingsCard>
  );
}

function ConflictRow({ parts, conflict, said }: { parts: SettingsParts; conflict: PersonalSyncConflict; said: (note: Note) => void }) {
  const { sync } = parts;
  const busy = sync.busy === conflict.id;
  const keep = (side: 'theirs' | 'mine') => void sync.resolve(conflict.id, side).then((outcome) => said(noteOf(outcome, '')));
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-panel-edge px-3.5 py-3">
      <div className="flex flex-col gap-0.5">
        <span className="text-body font-medium text-foreground">{conflict.name}</span>
        <span className="text-footnote text-muted">{conflictCaption(conflict, ago(conflict.keptAt, Date.now()))}</span>
      </div>
      <div className="grid grid-cols-2 gap-2.5">
        <Side title="Theirs" text={conflict.theirs} />
        <Side title="Mine" text={conflict.mine ?? 'Nothing by this name on this machine.'} />
      </div>
      <div className="flex gap-2">
        <KitButton disabled={busy} onClick={() => keep('theirs')}>
          Keep theirs
        </KitButton>
        <KitButton disabled={busy} onClick={() => keep('mine')}>
          Keep mine
        </KitButton>
      </div>
    </div>
  );
}

function Side({ title, text }: { title: string; text: string }) {
  return (
    <div className="flex min-w-0 flex-col gap-1">
      <span className="text-footnote font-medium text-muted">{title}</span>
      <pre className="max-h-48 overflow-auto rounded-md bg-raised px-2.5 py-2 font-mono text-micro whitespace-pre-wrap text-foreground">{text}</pre>
    </div>
  );
}
