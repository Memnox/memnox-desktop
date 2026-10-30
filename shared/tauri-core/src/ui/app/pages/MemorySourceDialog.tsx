import { KeyRound } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import { MEMORY_SCOPES, SOURCE_KINDS, emptySourceForm, sourceFormProblem, sourceInputOf, type SourceForm } from '../../../core/domain/memory-lines';
import { KitButton, SelectMenu } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { memoryNote } from './MemoryPage';
import { Dialog } from './SkillDialogs';

const FIELD = 'h-9 w-full rounded-lg border border-field-edge bg-field px-3 text-footnote text-foreground outline-none placeholder:text-faint focus:border-primary';

/**
 * Adds one place memory is read from. A key is never part of the form: it is named here, and set once
 * through the MCP Hub's secret store, so the source keeps only the name of the secret.
 */
export function AddMemorySourceDialog({ parts, close, said }: { parts: SettingsParts; close: () => void; said: (note: string) => void }) {
  const { memory, hub } = parts;
  useObserved(memory, hub);
  const [form, setForm] = useState<SourceForm>(() => emptySourceForm('obsidian'));
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const place = SOURCE_KINDS.find((each) => each.kind === form.kind)?.place;
  useEffect(() => {
    if (place === 'server' && hub.hub === undefined) void hub.refresh();
  }, [place]);
  const set = (change: Partial<SourceForm>) => setForm({ ...form, ...change });
  const send = () => {
    const wrong = sourceFormProblem(form);
    setProblem(wrong);
    if (wrong !== undefined) return;
    void memory.addSource(sourceInputOf(form)).then((outcome) => {
      if (outcome.kind === 'failed') {
        setProblem(outcome.why);
        return;
      }
      said(memoryNote(outcome));
      close();
    });
  };
  return (
    <Dialog
      title="Add a memory source"
      close={close}
      footer={
        <>
          <span className="flex-1 text-footnote text-muted">Your own agent reads it. Nothing it finds counts until you confirm it in Learn.</span>
          <KitButton onClick={close}>Cancel</KitButton>
          <KitButton kind="primary" disabled={memory.busy === 'add'} onClick={send}>
            {memory.busy === 'add' ? 'Adding' : 'Add'}
          </KitButton>
        </>
      }
    >
      <div className="flex flex-wrap gap-1.5" role="radiogroup" aria-label="Kind of source">
        {SOURCE_KINDS.map((each) => (
          <button
            key={each.kind}
            type="button"
            role="radio"
            aria-checked={form.kind === each.kind}
            onClick={() => {
              setForm({ ...emptySourceForm(each.kind), name: form.name, scope: form.scope });
              setProblem(undefined);
            }}
            className={`mx-focus cursor-pointer rounded-full border px-3 py-1 text-footnote ${form.kind === each.kind ? 'border-primary bg-hover font-medium text-foreground' : 'border-panel-edge text-muted hover:bg-hover'}`}
          >
            {each.label}
          </button>
        ))}
      </div>
      {(place === 'folder' || place === 'repository') && (
        <Labelled label={place === 'repository' ? 'The repository, from the top of the drive' : 'The folder, from the top of the drive'}>
          <input className={`${FIELD} font-mono`} value={form.location} placeholder={place === 'repository' ? '/home/you/code/project' : '/home/you/notes'} onChange={(event) => set({ location: event.target.value })} autoFocus />
          {place === 'repository' && <span className="text-footnote text-muted">Reads CLAUDE.md, AGENTS.md, GEMINI.md and .cursor/rules in it.</span>}
          {form.kind === 'notion-export' && <span className="text-footnote text-muted">The folder a Notion export unzipped into. A third party wrote it, so it is read as untrusted.</span>}
        </Labelled>
      )}
      {place === 'secret' && <SupermemoryKey parts={parts} secret={form.secret} setSecret={(secret) => set({ secret })} />}
      {place === 'server' && <HubServerPick parts={parts} form={form} set={set} />}
      <Labelled label="Name it, or leave it to be named for you">
        <input className={FIELD} value={form.name} placeholder="Team notes" onChange={(event) => set({ name: event.target.value })} />
      </Labelled>
      <Labelled label="Keep what it teaches">
        <SelectMenu
          label="Keep what it teaches"
          value={form.scope}
          options={MEMORY_SCOPES.map((each) => ({ value: each.scope, label: each.scope === 'personal' ? 'In my personal memory' : 'With the project' }))}
          onChange={(scope) => set({ scope })}
        />
      </Labelled>
      {problem !== undefined && (
        <p role="alert" className="text-footnote text-destructive">
          {problem}
        </p>
      )}
    </Dialog>
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
    void hub.setSecret(name, key).then((outcome) => {
      setKey('');
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
