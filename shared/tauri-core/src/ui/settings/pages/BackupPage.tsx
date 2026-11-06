import type { BackupSummary } from '@memnox/core/wire';
import { Archive, ClipboardCopy, Download, FileUp, History } from 'lucide-react';
import { useState } from 'react';
import { ARCHIVE_ACCEPT, archiveFileName, BackupLines, LEDGER_LINE, passphraseProblem, restoreWaitsLine, summaryLine } from '../../../core/domain/backup-lines';
import { SettingsCard, SettingsDivider, SettingsRow, SwitchRow, useCopied } from '../kit';
import type { SettingsParts } from '../parts';
import { Button, ErrorLine, Field, FilePicker, Input, TruncatedText } from '../../kit';

/** The file chooser's glyph, small and heavy beside 12.5 words. */
const CHOOSE_GLYPH = 12;
const CHOOSE_GLYPH_STROKE = 2.6;
/** The webview reads a download link after the click returns, so it is let go this long after. */
const DOWNLOAD_RELEASE_MS = 1_000;

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
    <SettingsCard title={BackupLines.makeTitle}>
      <p className="text-footnote text-muted">{BackupLines.makeDetail}</p>
      <PassphraseField label={BackupLines.passphrase} value={passphrase} onChange={setPassphrase} />
      <PassphraseField label={BackupLines.again} value={again} onChange={setAgain} onSubmit={() => void create()} />
      <SwitchRow icon={History} title={BackupLines.includeLedger} caption={LEDGER_LINE} on={ledger} onChange={setLedger} />
      {problem !== undefined && <ErrorLine>{problem}</ErrorLine>}
      <div className="flex gap-2">
        <Button kind="primary" icon={Archive} disabled={busy} onClick={() => void create()}>
          {busy ? BackupLines.sealing : BackupLines.create}
        </Button>
      </div>
      {made !== undefined && (
        <>
          <SettingsDivider full />
          <SettingsRow icon={Archive} title={BackupLines.made(new Date(made.summary.createdAt).toLocaleString())} caption={summaryLine(made.summary)}>
            <Button icon={ClipboardCopy} onClick={() => copy(made.archive)}>
              {copied ? BackupLines.copied : BackupLines.copy}
            </Button>
            <Button icon={Download} onClick={() => saveAsFile(made.archive, archiveFileName(made.summary.createdAt))}>
              {BackupLines.save}
            </Button>
          </SettingsRow>
          <p className="text-footnote text-muted">{BackupLines.keepApart}</p>
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
    if (archive === undefined) return setProblem(BackupLines.chooseFirst);
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
    <SettingsCard title={BackupLines.restoreTitle}>
      <p className="text-footnote text-muted">{BackupLines.restoreDetail(words.keyTitle)}</p>
      <label className="flex items-center gap-3">
        <span className="inline-flex cursor-pointer items-center gap-1.5 rounded-full border border-control-edge bg-secondary px-3 py-1 text-button font-medium text-foreground focus-within:border-primary">
          <FileUp size={CHOOSE_GLYPH} strokeWidth={CHOOSE_GLYPH_STROKE} aria-hidden />
          {BackupLines.chooseFile}
          <FilePicker
            accept={ARCHIVE_ACCEPT}
            className="sr-only"
            onFile={(file) => {
              setProposed(undefined);
              if (file === undefined) return setArchive(undefined);
              void file.text().then((text) => setArchive({ name: file.name, text }));
            }}
          />
        </span>
        <span className="min-w-0 truncate text-footnote text-muted">{archive === undefined ? BackupLines.noFile : archive.name}</span>
      </label>
      <PassphraseField label={BackupLines.itsPassphrase} value={passphrase} onChange={setPassphrase} onSubmit={() => void restore()} />
      {problem !== undefined && <ErrorLine>{problem}</ErrorLine>}
      <div className="flex gap-2">
        <Button kind="primary" icon={FileUp} disabled={busy} onClick={() => void restore()}>
          {busy ? BackupLines.reading : BackupLines.restore}
        </Button>
      </div>
      {proposed !== undefined && (
        <div role="status" className="flex flex-col gap-2 rounded-lg border border-panel-edge px-3.5 py-3">
          <p className="text-body text-foreground">{restoreWaitsLine(words.keyTitle)}</p>
          <p className="text-footnote text-muted">{BackupLines.madeAt(new Date(proposed.createdAt).toLocaleString(), summaryLine(proposed))}</p>
          <ul className="flex max-h-48 flex-col gap-0.5 overflow-y-auto font-code text-micro text-muted">
            {proposed.files.map((file) => (
              <li key={file} className="min-w-0 overflow-hidden">
                <TruncatedText text={file} middle />
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
    <Field label={label}>
      <Input type="password" autoComplete="new-password" wide value={value} placeholder={BackupLines.passphraseHint} aria-label={label} onValue={onChange} onSubmit={onSubmit} />
    </Field>
  );
}

/** Hands the archive to the webview as a download, which saves it where the system keeps downloads. */
function saveAsFile(archive: string, name: string): void {
  const url = URL.createObjectURL(new Blob([archive], { type: 'text/plain' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), DOWNLOAD_RELEASE_MS);
}
