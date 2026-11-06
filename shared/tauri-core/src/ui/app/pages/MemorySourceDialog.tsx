import { CircleAlert, FileText, Folder, KeyRound } from 'lucide-react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import {
  addedSources,
  addingLine,
  checkOf,
  fieldLabel,
  fieldOf,
  ImportLines,
  inputsOf,
  isZip,
  lastPart,
  panelExtensions,
  panelMessage,
  pathsOf,
  pickOf,
  picksFiles,
  placeholder,
  readingLine,
  resultLine,
  skippedLine,
  type ImportCheck,
  type ImportResult,
} from '../../../core/domain/memory-import';
import { MEMORY_SCOPES, moreLine, SOURCE_KINDS, emptySourceForm, sourceFormProblem, type SourceForm } from '../../../core/domain/memory-lines';
import { KitButton, SelectMenu, Spinner } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { StatusWord } from '../widgets';
import { Dialog } from './SkillDialogs';

const FIELD = 'h-9 w-full mx-field rounded-lg border border-field-edge bg-field px-3 text-footnote text-foreground outline-none placeholder:text-faint focus:border-primary';
/** The most lines the path field grows to before it scrolls, enough to see a few chosen files. */
const PATH_LINES = 4;
/** A pause after typing before the disk is looked at, so a path is not walked at every key. */
const LOOK_DELAY_MS = 300;
/** What this computer is called in a line that names it, as the Mac says "this Mac". */
const COMPUTER = 'computer';

/** Where the dialog is: the form, a source being added and read, or what the reads came to. */
type Stage = { kind: 'form' } | { kind: 'working'; line: string } | { kind: 'finished'; results: ImportResult[] };

/**
 * Adds one place memory is read from, as the Mac's sheet. A key is never part of the form: it is named here, and set
 * once through the MCP Hub's secret store, so the source keeps only the name of the secret. A file source may be
 * folders or files, picked, dropped or typed, and the dialog shows what will be read before it adds and what was read after.
 */
export function AddMemorySourceDialog({ parts, close, said }: { parts: SettingsParts; close: () => void; said: (note: string) => void }) {
  const { memory, hub, host } = parts;
  useObserved(memory, hub);
  const disk = host.memorySourceDisk;
  const [form, setForm] = useState<SourceForm>(() => emptySourceForm('obsidian'));
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const [check, setCheck] = useState<ImportCheck>({ kind: 'nothing' });
  const [stage, setStage] = useState<Stage>({ kind: 'form' });
  const [home, setHome] = useState<string | undefined>(undefined);
  const place = SOURCE_KINDS.find((each) => each.kind === form.kind)?.place;
  const files = place === 'folder' || place === 'repository';
  useEffect(() => void disk?.home().then(setHome), []);
  useEffect(() => {
    if (place === 'server' && hub.hub === undefined) void hub.refresh();
  }, [place]);
  // A newer path or kind starts a fresh look, and one still waiting is dropped.
  useEffect(() => {
    const paths = pathsOf(form.location, home);
    if (!files || paths.length === 0 || disk === undefined) {
      setCheck({ kind: 'nothing' });
      return;
    }
    let current = true;
    const timer = setTimeout(() => {
      void disk.look(paths, form.kind).then(
        (looks) => current && setCheck(checkOf(looks, form.kind, COMPUTER)),
        () => current && setCheck({ kind: 'nothing' }),
      );
    }, LOOK_DELAY_MS);
    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [form.kind, form.location, home]);

  // A path the look found wrong keeps Add from sending what the runtime would refuse.
  const blocked = files && check.kind === 'problem';
  const send = () => {
    const wrong = sourceFormProblem({ ...form, location: pathsOf(form.location, home)[0] ?? form.location });
    if (wrong !== undefined) return setProblem(wrong);
    if (files && check.kind === 'problem') return setProblem(check.why);
    setProblem(undefined);
    void add(form);
  };

  const add = async (sent: SourceForm) => {
    const paths = pathsOf(sent.location, home);
    let location = sent.location;
    if (files && paths.some(isZip)) {
      setStage({ kind: 'working', line: ImportLines.unzipping });
      const unzipped: string[] = [];
      for (const path of paths) {
        if (!isZip(path)) {
          unzipped.push(path);
          continue;
        }
        const answer = disk === undefined ? { why: `${lastPart(path)} could not be unzipped.` } : await disk.unzip(path);
        if ('why' in answer) {
          setStage({ kind: 'form' });
          setProblem(answer.why);
          return;
        }
        unzipped.push(answer.folder);
      }
      location = fieldOf(unzipped);
    }
    const inputs = inputsOf({ ...sent, location }, home);
    const results: ImportResult[] = [];
    for (const [index, input] of inputs.entries()) {
      const label = input.name ?? (input.location === undefined ? undefined : lastPart(input.location)) ?? SOURCE_KINDS.find((each) => each.kind === input.kind)?.label ?? input.kind;
      setStage({ kind: 'working', line: addingLine(label) });
      const before = (memory.sources ?? []).map((source) => source.id);
      const outcome = await memory.addSource(input);
      if (outcome.kind === 'failed') {
        // A single source refused goes back to its form, where the person can fix the path.
        if (inputs.length === 1) {
          setStage({ kind: 'form' });
          setProblem(outcome.why);
          return;
        }
        results.push({ name: label, failure: outcome.why });
        continue;
      }
      const added = addedSources(before, memory.sources ?? [])[0];
      if (added === undefined) {
        results.push({ name: label });
        continue;
      }
      setStage({ kind: 'working', line: readingLine(added.name, index + 1, inputs.length) });
      const read = await memory.readNow(added.id);
      const summary = memory.lastRead(added.id);
      if (summary === undefined && read.kind === 'failed') results.push({ name: added.name, failure: read.why });
      else results.push({ name: added.name, ...(summary === undefined ? {} : { summary }) });
    }
    said(ImportLines.pageNote);
    setStage({ kind: 'finished', results });
  };

  const footer =
    stage.kind === 'form' ? (
      <>
        <span className="flex-1 text-footnote text-muted">{ImportLines.formFooter}</span>
        <KitButton onClick={close}>Cancel</KitButton>
        <KitButton kind="primary" disabled={blocked} onClick={send}>
          Add
        </KitButton>
      </>
    ) : stage.kind === 'working' ? (
      <>
        <span className="flex-1 text-footnote text-muted">{ImportLines.workingFooter}</span>
        <KitButton onClick={close}>Close</KitButton>
      </>
    ) : (
      <>
        <span className="flex-1" />
        <KitButton
          onClick={() => {
            setForm({ ...emptySourceForm(form.kind), scope: form.scope });
            setProblem(undefined);
            setStage({ kind: 'form' });
          }}
        >
          {ImportLines.addAnother}
        </KitButton>
        <KitButton kind="primary" onClick={close}>
          {ImportLines.done}
        </KitButton>
      </>
    );

  return (
    <Dialog title="Add a memory source" close={close} footer={footer}>
      {stage.kind === 'working' && <ImportWorking line={stage.line} />}
      {stage.kind === 'finished' && <ImportFinished results={stage.results} />}
      {stage.kind === 'form' && (
        <>
          <Kinds
            form={form}
            choose={(kind, keepsPath) => {
              // A path stays when the next kind reads files too, so a wrong first chip costs nothing.
              const keep = files && keepsPath;
              setForm({ ...emptySourceForm(kind), location: keep ? form.location : '', name: form.name, scope: form.scope });
              setProblem(undefined);
            }}
          />
          {files && <PathField parts={parts} form={form} home={home} check={check} set={(location) => setForm({ ...form, location })} />}
          {place === 'secret' && <SupermemoryKey parts={parts} secret={form.secret} setSecret={(secret) => setForm({ ...form, secret })} />}
          {place === 'server' && <HubServerPick parts={parts} form={form} set={(change) => setForm({ ...form, ...change })} />}
          <Labelled label="Name it, or leave it to be named for you">
            <input className={FIELD} value={form.name} placeholder="Team notes" onChange={(event) => setForm({ ...form, name: event.target.value })} />
          </Labelled>
          <Labelled label="Keep what it teaches">
            <SelectMenu
              label="Keep what it teaches"
              value={form.scope}
              options={MEMORY_SCOPES.map((each) => ({ value: each.scope, label: each.scope === 'personal' ? 'In my personal memory' : 'With the project' }))}
              onChange={(scope) => setForm({ ...form, scope })}
            />
          </Labelled>
          {problem !== undefined && (
            <p role="alert" className="text-footnote text-destructive">
              {problem}
            </p>
          )}
        </>
      )}
    </Dialog>
  );
}

/** Two rows of three, as the Mac lays the six kinds so they fit the sheet's width. */
function Kinds({ form, choose }: { form: SourceForm; choose: (kind: SourceForm['kind'], keepsPath: boolean) => void }) {
  return (
    <div className="grid w-fit grid-cols-[repeat(3,auto)] justify-items-start gap-1.5" role="radiogroup" aria-label="Kind of source">
      {SOURCE_KINDS.map((each) => (
        <button
          key={each.kind}
          type="button"
          role="radio"
          aria-checked={form.kind === each.kind}
          onClick={() => choose(each.kind, each.place === 'folder' || each.place === 'repository')}
          className={`mx-focus cursor-pointer inline-flex h-8 items-center rounded-lg border px-3 text-body-sm ${form.kind === each.kind ? 'border-primary/45 bg-primary/[0.07] font-medium text-foreground' : 'border-panel-edge bg-card text-muted hover:bg-hover hover:text-foreground'}`}
        >
          {each.label}
        </button>
      ))}
    </div>
  );
}

/**
 * The folders or files to read: typed or pasted whole, one a line, dropped from the file manager, or chosen in the
 * system's dialog, with what the look on disk found said under it.
 */
function PathField({ parts, form, home, check, set }: { parts: SettingsParts; form: SourceForm; home: string | undefined; check: ImportCheck; set: (location: string) => void }) {
  const { host } = parts;
  const zone = useRef<HTMLDivElement>(null);
  const [dropping, setDropping] = useState(false);
  const label = fieldLabel(form.kind);
  // Held in a ref, so the window's drop listener is set once rather than at every key.
  const take = useRef(set);
  take.current = set;
  // The system reports a drop anywhere on the window, so only one over this field is taken.
  useEffect(
    () =>
      host.onFileDrop?.((drop) => {
        const box = zone.current?.getBoundingClientRect();
        const over = drop.kind !== 'leave' && box !== undefined && drop.x >= box.left && drop.x <= box.right && drop.y >= box.top && drop.y <= box.bottom;
        setDropping(drop.kind === 'over' && over);
        if (drop.kind === 'drop' && over && drop.paths.length > 0) take.current(fieldOf(drop.paths));
      }),
    [],
  );
  const choose = async () => {
    const pick = pickOf(form.kind);
    const chosen = await host.memorySourceDisk?.pick(picksFiles(pick), panelExtensions(pick), panelMessage(form.kind)).catch(() => undefined);
    if (chosen !== undefined && chosen.length > 0) set(fieldOf(chosen));
  };
  const lines = Math.min(PATH_LINES, Math.max(1, pathsOf(form.location, home).length));
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-footnote font-medium text-muted">{label}</span>
      <div ref={zone} className={`flex items-start gap-2 rounded-lg transition-[padding] ${dropping ? 'bg-primary/[0.08] p-1' : ''}`}>
        <textarea
          className={`${FIELD} h-auto resize-none py-2 font-mono leading-5`}
          rows={lines}
          value={form.location}
          placeholder={placeholder(form.kind, home)}
          aria-label={label}
          autoFocus
          onChange={(event) => set(event.target.value)}
        />
        {host.memorySourceDisk !== undefined && (
          <KitButton icon={Folder} title={panelMessage(form.kind)} onClick={() => void choose()}>
            {ImportLines.choose}
          </KitButton>
        )}
      </div>
      <span className="text-footnote text-muted">{ImportLines.dropHint}</span>
      <ImportCheckView check={check} />
      {form.kind === 'instructions' && check.kind === 'nothing' && <span className="text-footnote text-muted">{ImportLines.instructionsHint}</span>}
      {form.kind === 'notion-export' && check.kind === 'nothing' && <span className="text-footnote text-muted">{ImportLines.notionHint}</span>}
    </div>
  );
}

/** What the look on disk found: why the path will not do, or what will be read from it. */
function ImportCheckView({ check }: { check: ImportCheck }) {
  if (check.kind === 'nothing') return null;
  if (check.kind === 'problem') {
    return (
      <span className="flex items-start gap-1.5 text-footnote text-destructive">
        <CircleAlert size={13} className="mt-0.5 shrink-0" aria-hidden />
        <span className="min-w-0 break-words">{check.why}</span>
      </span>
    );
  }
  const { preview } = check;
  const more = moreLine(preview.more);
  return (
    <div className="flex flex-col gap-1.5 rounded-lg border border-border bg-background p-3">
      <span className="flex items-center gap-1.5 text-body-sm font-medium text-foreground">
        <FileText size={14} className="shrink-0 text-muted" aria-hidden />
        {preview.headline}
      </span>
      {preview.names.map((name) => (
        <MiddleCut key={name} text={name} />
      ))}
      {more !== undefined && <span className="text-footnote text-muted">{more}</span>}
      {preview.note !== undefined && <span className="text-footnote text-muted">{preview.note}</span>}
    </div>
  );
}

/** One name in mono cut in its middle, so both ends of a long path read. */
function MiddleCut({ text }: { text: string }) {
  const half = Math.ceil(text.length / 2);
  return (
    <span title={text} className="flex min-w-0 font-code text-meta text-muted">
      <span className="truncate">{text.slice(0, half)}</span>
      <span className="shrink-0 whitespace-pre">{text.slice(half)}</span>
    </span>
  );
}

/** A source being added and read, said while the person's agent works. */
function ImportWorking({ line }: { line: string }) {
  return (
    <div role="status" className="flex items-start gap-3">
      <span className="mt-0.5">
        <Spinner />
      </span>
      <span className="text-body-sm text-foreground">{line}</span>
    </div>
  );
}

/** What each first read came to: what was read, what it passed over and why, or why a source was not added. */
function ImportFinished({ results }: { results: readonly ImportResult[] }) {
  return (
    <div className="flex flex-col gap-4">
      {results.map((result, at) => {
        const failed = result.failure !== undefined || result.summary?.error !== undefined;
        const skipped = skippedLine(result.summary?.skipped);
        return (
          <div key={at} className="flex flex-col gap-1.5">
            <div className="flex items-center gap-2">
              <span className="min-w-0 flex-1 truncate text-body font-semibold text-foreground">{result.name}</span>
              <StatusWord tone={failed ? 'bad' : 'good'}>{failed ? ImportLines.notRead : ImportLines.read}</StatusWord>
            </div>
            <span className={`text-footnote ${failed ? 'text-destructive' : 'text-foreground'}`}>{resultLine(result)}</span>
            {skipped !== undefined && <span className="text-footnote text-warm">{skipped}</span>}
          </div>
        );
      })}
      <span className="text-footnote text-muted">{ImportLines.finishedNote}</span>
    </div>
  );
}

function Labelled({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-footnote font-medium text-muted">{label}</span>
      {children}
    </label>
  );
}

/** The secret's name goes with the source; the key itself goes once into the hub's store and is cleared here. */
function SupermemoryKey({ parts, secret, setSecret }: { parts: SettingsParts; secret: string; setSecret: (secret: string) => void }) {
  const { hub } = parts;
  const [key, setKey] = useState('');
  const [note, setNote] = useState<string | undefined>(undefined);
  const save = () => {
    const name = secret.trim();
    if (name === '' || key === '') return;
    // The key leaves this view at once and nothing here keeps a copy.
    const value = key;
    setKey('');
    void hub.setSecret(name, value).then((outcome) => {
      if (outcome.kind === 'failed') setNote(outcome.why);
      else if (outcome.kind === 'proposed') setNote('Waiting for your signature on the island before the key is kept.');
      else setNote(`${name} is kept by this computer now.`);
    });
  };
  return (
    <>
      <Labelled label="The name of the secret that holds the key">
        <input className={`${FIELD} font-mono`} value={secret} onChange={(event) => setSecret(event.target.value)} />
      </Labelled>
      <div className="flex flex-col gap-1.5">
        <span className="text-footnote font-medium text-muted">Set the key</span>
        <div className="flex gap-2">
          <input className={FIELD} type="password" autoComplete="off" value={key} placeholder="Paste the Supermemory key" aria-label="Set the key" onChange={(event) => setKey(event.target.value)} />
          <KitButton icon={KeyRound} disabled={key === '' || secret.trim() === '' || hub.busy === secret.trim()} onClick={save}>
            Set the key
          </KitButton>
        </div>
        <span className="text-footnote text-muted">{note ?? 'Kept by this computer’s own store with the MCP Hub’s secrets. The source keeps only its name, and it is read as untrusted.'}</span>
      </div>
    </>
  );
}

/** A server from the hub and the tool that reads its memory, typed when the hub has not listed its tools. */
function HubServerPick({ parts, form, set }: { parts: SettingsParts; form: SourceForm; set: (change: Partial<SourceForm>) => void }) {
  const servers = parts.hub.hub?.servers ?? [];
  const server = servers.find((each) => each.name === form.server);
  const tools = server?.tools ?? [];
  if (servers.length === 0) {
    return <p className="text-footnote text-muted">{parts.hub.hub === undefined ? 'Reading the MCP Hub.' : 'The MCP Hub on this computer has no servers yet. Add the memory server there first.'}</p>;
  }
  return (
    <>
      <Labelled label="The hub server">
        <SelectMenu
          label="The hub server"
          value={form.server}
          options={[{ value: '', label: 'Choose a server' }, ...servers.map((each) => ({ value: each.name, label: each.name }))]}
          onChange={(name) => set({ server: name, tool: '' })}
        />
      </Labelled>
      {server !== undefined && (
        <Labelled label="The tool that reads its memory">
          {tools.length > 0 ? (
            <SelectMenu label="The tool that reads its memory" value={form.tool} options={[{ value: '', label: 'Choose a tool' }, ...tools.map((each) => ({ value: each.name, label: each.name }))]} onChange={(tool) => set({ tool })} />
          ) : (
            <input className={`${FIELD} font-mono`} value={form.tool} placeholder="search_memory" onChange={(event) => set({ tool: event.target.value })} />
          )}
        </Labelled>
      )}
      <span className="text-footnote text-muted">A server outside your own files is read as untrusted.</span>
    </>
  );
}
