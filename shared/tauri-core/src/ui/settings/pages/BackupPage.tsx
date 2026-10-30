import type { BackupSummary } from '@memnox/core/wire';
import { Archive, ClipboardCopy, Download, FileUp, History } from 'lucide-react';
import { useState } from 'react';
import { archiveFileName, LEDGER_LINE, passphraseProblem, restoreWaitsLine, summaryLine } from '../../../core/domain/backup-lines';
import { KitButton, SettingsCard, SettingsDivider, SettingsRow, SwitchRow, useCopied } from '../kit';
import type { SettingsParts } from '../parts';

const FIELD = 'h-8 w-full rounded-[7px] border border-control-edge bg-raised px-2.5 text-body text-foreground outline-none placeholder:text-muted focus:border-primary';

/**
 * Backing up what was set up on this computer and putting it back. The runtime seals the archive and never
 * holds the passphrase; putting one back is only proposed here, and holds once signed on the island.
 */
export function BackupPage({ parts }: { parts: SettingsParts }) {
  return (
    <>
      <CreateCard parts={parts} />
      <RestoreCard parts={parts} />
    </>
  );
}

function CreateCard({ parts }: { parts: SettingsParts }) {
  const { backup, host } = parts;
  const [passphrase, setPassphrase] = useState('');
  const [again, setAgain] = useState('');
  const [ledger, setLedger] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const [made, setMade] = useState<{ archive: string; summary: BackupSummary } | undefined>(undefined);
  const [copied, copy] = useCopied((text) => host.copy(text));

  const create = async () => {
    const wrong = passphraseProblem(passphrase, again);
    setProblem(wrong);
    if (wrong !== undefined) return;
    setBusy(true);
    const outcome = await backup.create(passphrase, ledger);
    setBusy(false);
    if (outcome.kind === 'failed') return setProblem(outcome.why);
    // The passphrase is never kept past the press that used it.
    setPassphrase('');
    setAgain('');
    setMade({ archive: outcome.archive, summary: outcome.summary });
  };

  return (
    <SettingsCard title="Make a backup">
      <p className="text-footnote text-muted">Rules, the MCP Hub, skills, projects and memory, sealed under a passphrase. No secret is ever put in it.</p>
      <PassphraseField label="Passphrase" value={passphrase} onChange={setPassphrase} />
      <PassphraseField label="The same passphrase again" value={again} onChange={setAgain} onSubmit={() => void create()} />
      <SwitchRow icon={History} title="Include the ledger" caption={LEDGER_LINE} on={ledger} onChange={setLedger} />
      {problem !== undefined && (
        <p role="alert" className="text-footnote text-destructive">
          {problem}
        </p>
      )}
      <div className="flex gap-2">
        <KitButton kind="primary" icon={Archive} disabled={busy} onClick={() => void create()}>
          {busy ? 'Sealing' : 'Create backup'}
        </KitButton>
      </div>
      {made !== undefined && (
        <>
          <SettingsDivider full />
          <SettingsRow icon={Archive} title={`Made ${new Date(made.summary.createdAt).toLocaleString()}`} caption={summaryLine(made.summary)}>
            <KitButton icon={ClipboardCopy} onClick={() => copy(made.archive)}>
              {copied ? 'Copied' : 'Copy'}
            </KitButton>
            <KitButton icon={Download} onClick={() => saveAsFile(made.archive, archiveFileName(made.summary.createdAt))}>
              Save as a file
            </KitButton>
          </SettingsRow>
          <p className="text-footnote text-muted">Keep the passphrase somewhere apart from the file. Without it nobody, Memnox included, can open this backup.</p>
        </>
      )}
    </SettingsCard>
  );
}

function RestoreCard({ parts }: { parts: SettingsParts }) {
  const { backup, words } = parts;
  const [archive, setArchive] = useState<{ name: string; text: string } | undefined>(undefined);
  const [passphrase, setPassphrase] = useState('');
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const [proposed, setProposed] = useState<BackupSummary | undefined>(undefined);

  const restore = async () => {
    if (archive === undefined) return setProblem('Choose the backup file first.');
    const wrong = passphraseProblem(passphrase, undefined);
    setProblem(wrong);
    if (wrong !== undefined) return;
    setBusy(true);
    const outcome = await backup.restore(archive.text, passphrase);
    setBusy(false);
    if (outcome.kind === 'failed') return setProblem(outcome.why);
    setPassphrase('');
    setProposed(outcome.summary);
  };

  return (
    <SettingsCard title="Put a backup back">
      <p className="text-footnote text-muted">{`Choose the file and type its passphrase. Memnox reads what it holds and asks for your signature with ${words.keyTitle} on the island before it puts anything back.`}</p>
      <label className="flex items-center gap-3">
        <span className="inline-flex cursor-pointer items-center gap-1.5 rounded-full border border-control-edge bg-secondary px-3 py-1 text-button font-medium text-foreground focus-within:border-primary">
          <FileUp size={12} strokeWidth={2.6} aria-hidden />
          Choose a file
          <input
            type="file"
            accept=".txt,text/plain"
            className="sr-only"
            onChange={(event) => {
              const file = event.target.files?.[0];
              setProposed(undefined);
              if (file === undefined) return setArchive(undefined);
              void file.text().then((text) => setArchive({ name: file.name, text }));
            }}
          />
        </span>
        <span className="min-w-0 truncate text-footnote text-muted">{archive === undefined ? 'No file chosen' : archive.name}</span>
      </label>
      <PassphraseField label="Its passphrase" value={passphrase} onChange={setPassphrase} onSubmit={() => void restore()} />
      {problem !== undefined && (
        <p role="alert" className="text-footnote text-destructive">
          {problem}
        </p>
      )}
      <div className="flex gap-2">
        <KitButton kind="primary" icon={FileUp} disabled={busy} onClick={() => void restore()}>
          {busy ? 'Reading' : 'Restore'}
        </KitButton>
      </div>
      {proposed !== undefined && (
        <div role="status" className="flex flex-col gap-2 rounded-lg border border-panel-edge px-3.5 py-3">
          <p className="text-body text-foreground">{restoreWaitsLine(words.keyTitle)}</p>
          <p className="text-footnote text-muted">{`Made ${new Date(proposed.createdAt).toLocaleString()}: ${summaryLine(proposed)}`}</p>
          <ul className="flex max-h-48 flex-col gap-0.5 overflow-y-auto font-mono text-micro text-muted">
            {proposed.files.map((file) => (
              <li key={file} className="truncate">
                {file}
              </li>
            ))}
          </ul>
        </div>
      )}
    </SettingsCard>
  );
}

function PassphraseField({ label, value, onChange, onSubmit }: { label: string; value: string; onChange: (value: string) => void; onSubmit?: () => void }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-footnote font-medium text-muted">{label}</span>
      <input
        type="password"
        autoComplete="new-password"
        className={FIELD}
        value={value}
        placeholder="At least 10 characters"
        onChange={(event) => onChange(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === 'Enter' && onSubmit !== undefined) onSubmit();
        }}
      />
    </label>
  );
}

/** Hands the archive to the webview as a download, which saves it where the system keeps downloads. */
function saveAsFile(archive: string, name: string): void {
  const url = URL.createObjectURL(new Blob([archive], { type: 'text/plain' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  // The webview reads the link after the click returns, so it is let go a moment later.
  setTimeout(() => URL.revokeObjectURL(url), 1_000);
}
