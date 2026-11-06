import { CircleAlert, FileText, Folder, KeyRound } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
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
import { useObserved, type SettingsParts } from '../../settings/parts';
import { KitLines } from '../../../core/domain/kit-lines';
import { Button, Chip, Dialog, ErrorLine, Field, Input, Select, Spinner, StatusWord, Textarea, TruncatedText } from '../../kit';

/** The warning beside a path that will not do, a point over its footnote. */
const CHECK_GLYPH = 13;

/** The file glyph beside what will be read, as the button glyphs are. */
const PREVIEW_GLYPH = 14;

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
        <Button kind="primary" disabled={blocked} onClick={send}>
          {ImportLines.add}
        </Button>
      </>
    ) : stage.kind === 'working' ? (
      <>
        <span className="flex-1 text-footnote text-muted">{ImportLines.workingFooter}</span>
      </>
    ) : (
      <>
        <span className="flex-1" />
        <Button
          onClick={() => {
            setForm({ ...emptySourceForm(form.kind), scope: form.scope });
            setProblem(undefined);
            setStage({ kind: 'form' });
          }}
        >
          {ImportLines.addAnother}
        </Button>
        <Button kind="primary" onClick={close}>
          {ImportLines.done}
        </Button>
      </>
    );

  return (
    <Dialog title={ImportLines.title} close={close} cancel={stage.kind === 'form' ? KitLines.cancel : stage.kind === 'working' ? KitLines.close : null} actions={footer}>
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
          <Field label={ImportLines.nameLabel}>
            <Input wide value={form.name} placeholder={ImportLines.namePlaceholder} onValue={(name) => setForm({ ...form, name })} />
          </Field>
          <Field label={ImportLines.keepLabel}>
            <Select
              label={ImportLines.keepLabel}
              value={form.scope}
              options={MEMORY_SCOPES.map((each) => ({ value: each.scope, label: each.scope === 'personal' ? ImportLines.keepPersonal : ImportLines.keepProject }))}
              onChange={(scope) => setForm({ ...form, scope })}
            />
          </Field>
          {problem !== undefined && <ErrorLine>{problem}</ErrorLine>}
        </>
      )}
    </Dialog>
  );
}

/** Two rows of three, as the Mac lays the six kinds so they fit the sheet's width. */
function Kinds({ form, choose }: { form: SourceForm; choose: (kind: SourceForm['kind'], keepsPath: boolean) => void }) {
  return (
    <div className="grid w-fit grid-cols-[repeat(3,auto)] justify-items-start gap-1.5" role="radiogroup" aria-label={ImportLines.kindsLabel}>
      {SOURCE_KINDS.map((each) => (
        <Chip key={each.kind} role="radio" on={form.kind === each.kind} pick={() => choose(each.kind, each.place === 'folder' || each.place === 'repository')}>
          {each.label}
        </Chip>
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
      <div ref={zone} className={`flex items-start gap-2 rounded-control transition-[padding] ${dropping ? 'bg-primary/[0.08] p-1' : ''}`}>
        <Textarea mono className="resize-none leading-5" rows={lines} value={form.location} placeholder={placeholder(form.kind, home)} aria-label={label} autoFocus onValue={set} />
        {host.memorySourceDisk !== undefined && (
          <Button icon={Folder} title={panelMessage(form.kind)} onClick={() => void choose()}>
            {ImportLines.choose}
          </Button>
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
        <CircleAlert size={CHECK_GLYPH} className="mt-0.5 shrink-0" aria-hidden />
        <span className="min-w-0 break-words">{check.why}</span>
      </span>
    );
  }
  const { preview } = check;
  const more = moreLine(preview.more);
  return (
    <div className="flex flex-col gap-1.5 rounded-control border border-border bg-background p-3">
      <span className="flex items-center gap-1.5 text-body-sm font-medium text-foreground">
        <FileText size={PREVIEW_GLYPH} className="shrink-0 text-muted" aria-hidden />
        {preview.headline}
      </span>
      {preview.names.map((name) => (
        <TruncatedText key={name} middle text={name} className="font-code text-meta text-muted" />
      ))}
      {more !== undefined && <span className="text-footnote text-muted">{more}</span>}
      {preview.note !== undefined && <span className="text-footnote text-muted">{preview.note}</span>}
    </div>
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
      else if (outcome.kind === 'proposed') setNote(ImportLines.keyWaiting);
      else setNote(ImportLines.keyKept(name));
    });
  };
  return (
    <>
      <Field label={ImportLines.secretName}>
        <Input wide mono value={secret} onValue={setSecret} />
      </Field>
      <div className="flex flex-col gap-1.5">
        <span className="text-footnote font-medium text-muted">{ImportLines.setKey}</span>
        <div className="flex gap-2">
          <Input wide type="password" autoComplete="off" value={key} placeholder={ImportLines.keyPlaceholder} aria-label={ImportLines.setKey} onValue={setKey} />
          <Button icon={KeyRound} disabled={key === '' || secret.trim() === '' || hub.busy === secret.trim()} onClick={save}>
            {ImportLines.setKey}
          </Button>
        </div>
        <span className="text-footnote text-muted">{note ?? ImportLines.keyNote}</span>
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
    return <p className="text-footnote text-muted">{parts.hub.hub === undefined ? ImportLines.readingHub : ImportLines.noHubServers}</p>;
  }
  return (
    <>
      <Field label={ImportLines.hubServer}>
        <Select
          label={ImportLines.hubServer}
          value={form.server}
          none={ImportLines.chooseServer}
          options={servers.map((each) => ({ value: each.name, label: each.name }))}
          onChange={(name) => set({ server: name, tool: '' })}
        />
      </Field>
      {server !== undefined && (
        <Field label={ImportLines.hubTool}>
          {tools.length > 0 ? (
            <Select label={ImportLines.hubTool} value={form.tool} none={ImportLines.chooseTool} options={tools.map((each) => ({ value: each.name, label: each.name }))} onChange={(tool) => set({ tool })} />
          ) : (
            <Input wide mono value={form.tool} placeholder={ImportLines.toolPlaceholder} onValue={(tool) => set({ tool })} />
          )}
        </Field>
      )}
      <span className="text-footnote text-muted">{ImportLines.serverUntrusted}</span>
    </>
  );
}
